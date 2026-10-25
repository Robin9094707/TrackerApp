"""Focused Apple auth regression checks, temporary data and no account/network."""
import asyncio
import base64
import copy
import json
import os
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_backend_calendar_mcp import M, APP, STATE
G = M['validate_apple_runtime'].__globals__


class AppleAuthTests(unittest.TestCase):
    def setUp(self):
        self.original = {k: STATE.get(k) for k in ('account','temp_acc','twofa_methods','selected_method','sync_failures','sync_backoff_until','apple_login_retry_after')}
        STATE.update(account=None,temp_acc=None,twofa_methods=None,selected_method=None,apple_login_retry_after=0)
        self.client=APP.test_client()
        pair=self.client.post('/api/mobile/v1/pair',json={'pw':'Regression-Test-Password'})
        self.headers={'X-CSRF-Token':pair.json['csrf_token']}
        self.persist=Mock()
        self.cleanup=Mock()
        self.patches=patch.dict(G,validate_apple_runtime=Mock(),persist_apple_account=self.persist,close_apple_account=self.cleanup)
        self.patches.start()

    def tearDown(self):
        self.patches.stop()
        STATE.update(self.original)

    def account(self, tokens=True):
        acc=Mock()
        acc.login_state=M['LoginState'].LOGGED_IN
        acc.login.return_value=acc.login_state
        acc.to_json.return_value={'login':{'data':{'mobileme_data':{'tokens':{'searchPartyToken':'offline-fixture'} if tokens else {}}}}}
        return acc

    def login(self):
        return self.client.post('/api/login',json={'email':'fixture@example.test','password':'fixture-secret'},headers=self.headers)

    def test_provider_rejection_is_specific_and_does_not_replace_account(self):
        old=object();STATE['account']=old
        acc=self.account();acc.login.side_effect=RuntimeError('Email verification failed: This action cannot be completed at this time.')
        with patch.dict(G,AppleAccount=Mock(return_value=acc)):
            response=self.login()
            self.assertEqual(response.json['code'],'apple_provider_rejected')
            self.assertNotIn('fixture-secret',response.get_data(as_text=True))
            self.assertIs(STATE['account'],old)
            self.persist.assert_not_called()
            self.assertEqual(self.login().status_code,429)
            self.assertEqual(acc.login.call_count,1)

    def test_missing_token_never_reports_success_or_overwrites_session(self):
        old=object();STATE['account']=old
        acc=self.account(tokens=False)
        with patch.dict(G,AppleAccount=Mock(return_value=acc)):
            response=self.login()
        self.assertEqual(response.status_code,400)
        self.assertIn('searchPartyToken',response.json['message'])
        self.assertIs(STATE['account'],old)
        self.persist.assert_not_called()
        self.cleanup.assert_called_with(acc)

    def test_direct_login_persists_and_resets_old_poll_backoff(self):
        acc=self.account();STATE.update(sync_failures=8,sync_backoff_until=10**12)
        with patch.dict(G,AppleAccount=Mock(return_value=acc)):
            response=self.login()
        self.assertEqual(response.json['status'],'success')
        self.persist.assert_called_once_with(acc)
        self.assertIs(STATE['account'],acc)
        self.assertEqual(STATE['sync_backoff_until'],0)
        self.assertEqual(STATE['sync_failures'],0)

    def test_2fa_keeps_old_session_until_token_is_ready(self):
        old=object();STATE['account']=old
        STATE['selected_method']=object()
        acc=self.account();acc.login_state=M['LoginState'].REQUIRE_2FA
        acc.login.return_value=acc.login_state
        method=Mock(phone_number='fixture')
        method.submit.side_effect=lambda _: setattr(acc,'login_state',M['LoginState'].LOGGED_IN)
        acc.get_2fa_methods.return_value=[method]
        with patch.dict(G,AppleAccount=Mock(return_value=acc)):
            self.assertEqual(self.login().json['status'],'2fa')
        self.assertIsNone(STATE['selected_method'])
        self.assertIs(STATE['account'],old)
        self.assertEqual(self.client.post('/api/2fa/request',json={'index':0},headers=self.headers).status_code,200)
        response=self.client.post('/api/2fa/submit',json={'code':'123456'},headers=self.headers)
        self.assertEqual(response.json['status'],'success')
        self.assertIs(STATE['account'],acc)
        self.assertIsNone(STATE['temp_acc'])
        self.persist.assert_called_once_with(acc)

    def test_account_operations_are_serialized_with_polling(self):
        lock=M['fetch_lock'];lock.acquire()
        try:
            self.assertEqual(self.login().status_code,409)
            self.assertEqual(self.client.post('/api/apple/auth/logout',headers=self.headers).status_code,409)
        finally:lock.release()
        self.persist.assert_not_called()

    def test_setup_failure_is_actionable(self):
        with patch.dict(G,validate_apple_runtime=Mock(side_effect=M['AppleSetupError']('Bitte install-apple-backend.sh ausführen.'))):
            response=self.login()
        self.assertEqual(response.json['code'],'apple_setup_required')
        self.assertIn('install-apple-backend.sh',response.json['message'])

    def test_legacy_session_is_preserved_for_reauthentication(self):
        path=Path(os.fspath(M['ACCOUNT_FILE']))
        old=path.read_bytes() if path.exists() else None
        legacy=json.dumps({'type':'account','anisette':{'type':'aniLocal','prov_data':base64.b64encode(b'PK-legacy-provisioning').decode()}}).encode()
        try:
            path.write_bytes(legacy)
            self.assertIsNone(M['restore_apple_account']())
            self.assertEqual(STATE['apple_session_restore']['status'],'reauth_required')
            self.assertEqual(path.read_bytes(),legacy)
        finally:
            if old is None:path.unlink(missing_ok=True)
            else:path.write_bytes(old)

    def test_restore_does_not_pass_android_library_cache(self):
        path=Path(os.fspath(M['ACCOUNT_FILE']))
        old=path.read_bytes() if path.exists() else None
        modern=base64.b64encode(json.dumps({'device':{},'adi_pb':None}).encode()).decode()
        factory=Mock();acc=object();factory.from_json.return_value=acc
        try:
            path.write_text(json.dumps({'type':'account','anisette':{'type':'aniLocal','prov_data':modern}}))
            with patch.dict(G,AppleAccount=factory):
                self.assertIs(M['restore_apple_account'](),acc)
            factory.from_json.assert_called_once_with(path)
        finally:
            if old is None:path.unlink(missing_ok=True)
            else:path.write_bytes(old)

    def test_gsa_user_agent_follows_provider_and_tls_stays_enabled(self):
        provider=SimpleNamespace(user_agent='akd/1.0 CFNetwork/3860.100.1 Darwin/25.0.0')
        http=M['AppleIdentityHttpSession'](provider)
        async def call():
            try:
                with patch.object(M['FindMyHttpSession'],'request',new=__import__('unittest.mock',fromlist=['AsyncMock']).AsyncMock()) as request:
                    await http.request('POST','https://gsa.apple.com/grandslam/GsService2',headers={'User-Agent':'old'})
                    self.assertEqual(request.call_args.kwargs['headers']['User-Agent'],provider.user_agent)
                    await http.request('GET','https://example.test',headers={'User-Agent':'original'})
                    self.assertEqual(request.call_args.kwargs['headers']['User-Agent'],'original')
                    self.assertIsNot(http._ssl,False)
            finally:await http.close()
        asyncio.run(call())

    def test_official_binary_boots_without_account_and_state_round_trips(self):
        binary=Path(os.environ['MACOS_ADI_BINARY'])
        if not binary.is_file():self.skipTest('Run setup_apple_adi.py for the optional real binary check')
        from apple_adi import ITunesADI
        async def run():
            adi=ITunesADI('offline-fixture',None)
            self.assertFalse(await adi.is_machine_provisioned())
            restored=ITunesADI('offline-fixture',adi.adi_pb)
            self.assertFalse(await restored.is_machine_provisioned())
            self.assertEqual(restored.host_uuid,adi.host_uuid)
            with self.assertRaises(ValueError):ITunesADI('other-fixture',adi.adi_pb)
        asyncio.run(run())


if __name__=='__main__':unittest.main()
