"""Focused 4.3 regression suite; only temporary data, no network polling."""
import copy
import hashlib
import html
import json
import os
from pathlib import Path
import re
import runpy
import tempfile
import time
import unittest
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parents[1]
TEMP = tempfile.TemporaryDirectory()
DATA = Path(TEMP.name)
os.environ.update(ULTRA_TRACKER_DATA_DIR=str(DATA), ULTRA_TRACKER_DISABLE_BACKGROUND='1',
                  ULTRA_TRACKER_PASSWORD='Regression-Test-Password', ULTRA_TRACKER_TIMEZONE='Europe/Berlin')
# Load existing-format stores before the new backend starts.
legacy_point = {'lat': 51.43, 'lon': 6.76, 'acc': 12, 'ts': time.time()-300,
                'report_id': 'existing-report', 'received_at': time.time()-10, 'battery': '77 %'}
for relative in ('seven_day_history.json', 'google/history.json', 'samsung/history.json'):
    file = DATA / relative; file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(json.dumps({'legacy': {'enabled': True, 'points': [legacy_point]}}))
(DATA/'schema_version.json').write_text(json.dumps({'version':'19.0','migrated_ts':1}))
M = runpy.run_path(str(ROOT/'Backend/tracker_backend.py'))
STATE = M['state']
APP = M['app']

class BackendUpgradeTests(unittest.TestCase):
    def setUp(self):
        self.client = APP.test_client()
        pair = self.client.post('/api/mobile/v1/pair',json={'pw':'Regression-Test-Password'})
        self.assertEqual(pair.status_code,200)
        self.headers = {'X-CSRF-Token':pair.json['csrf_token']}
        STATE['google_devices'] = {'test':{'name':'Calendar test'}}
        STATE['google_history']['test'] = {'enabled':True,'points':[]}
        STATE['mcp_server'].update(enabled=True,public_base_url='https://tracker.example',allow_actions=True)
        STATE['mcp_oauth'] = M['default_mcp_oauth_store']()
        M['mcp_save_config']()
        M['mcp_save_oauth']()

    def point(self,day,offset=3600,report=None):
        start,_ = M['local_day_bounds'](day)
        return {'lat':51.43,'lon':6.76,'acc':12,'ts':start+offset,
                'report_id':report or day,'received_at':time.time()}

    def test_existing_stores_survive_startup(self):
        for key in ('seven_day_history','google_history','samsung_history'):
            row=STATE[key]['legacy']['points'][0]
            self.assertEqual(row['report_id'],'existing-report')
            self.assertEqual(row['battery'],'77 %')
            self.assertEqual(row['received_at'],legacy_point['received_at'])

    def test_calendar_days_obey_dst(self):
        for day,hours in [('2026-03-29',23),('2026-10-25',25),('2026-10-08',24)]:
            start,end=M['local_day_bounds'](day)
            self.assertEqual(end-start,hours*3600)
            w=M['mcp_time_window']({'dates':[day]})
            self.assertEqual(w['since_ts'],start)
            self.assertEqual(w['until_ts'],end-1)

    def test_non_adjacent_dates_and_midnight_boundaries(self):
        start,end=M['local_day_bounds']('2026-10-07')
        STATE['google_history']['test']['points']=[
            self.point('2026-10-07',0,'midnight'),self.point('2026-10-07',end-start-1,'last-second'),
            self.point('2026-10-08',0,'excluded-midnight'),self.point('2026-10-09',0,'today')]
        r=self.client.get('/api/mobile/v1/history',query_string={'ref':'google:test','dates':'2026-10-07,2026-10-09','resolve_addresses':'0'})
        self.assertEqual(r.status_code,200,r.json)
        self.assertEqual({p['report_id'] for p in r.json['points']},{'midnight','last-second','today'})

    def test_invalid_dates_do_not_mutate_history(self):
        before=copy.deepcopy(STATE['google_history'])
        for dates in ('2026-02-30','2026-1-1','not-a-date'):
            r=self.client.get('/api/mobile/v1/history',query_string={'ref':'google:test','dates':dates})
            self.assertEqual(r.status_code,400)
        self.assertEqual(STATE['google_history'],before)

    def test_calendar_includes_days_older_than_90_days(self):
        STATE['google_history']['test']['points']=[self.point('2026-03-29'),self.point('2026-10-08')]
        before=copy.deepcopy(STATE['google_history'])
        r=self.client.get('/api/mobile/v1/history/days?ref=google:test')
        self.assertEqual(r.status_code,200,r.json)
        self.assertEqual([d['date'] for d in r.json['days']],['2026-10-08','2026-03-29'])
        self.assertEqual(r.json['timezone'],'Europe/Berlin')
        self.assertEqual(STATE['google_history'],before)

    def test_stream_paging_scope_and_late_old_reports(self):
        STATE['google_history']['test']['points']=[self.point('2026-10-07',100,'one'),self.point('2026-10-09',200,'two'),self.point('2026-10-08',300,'excluded')]
        query={'ref':'google:test','dates':'2026-10-07,2026-10-09','limit':1}
        first=self.client.get('/api/mobile/v1/history/stream',query_string=query).json
        self.assertTrue(first['has_more'])
        second=self.client.get('/api/mobile/v1/history/stream',query_string={**query,'cursor':first['next_cursor']}).json
        self.assertFalse(second['has_more'])
        self.assertEqual({p['report_id'] for p in first['points']+second['points']},{'one','two'})
        wrong=self.client.get('/api/mobile/v1/history/stream',query_string={**query,'dates':'2026-10-08','cursor':first['next_cursor']})
        self.assertEqual(wrong.status_code,400)
        late=self.point('2026-10-07',400,'late');late['received_at']=time.time()+1
        STATE['google_history']['test']['points'].append(late)
        r=self.client.get('/api/mobile/v1/history/stream',query_string={**query,'cursor':second['next_cursor']}).json
        self.assertEqual(r['points'][0]['report_id'],'late')

    def test_inbox_bulk_actions_preserve_settings_and_history(self):
        STATE['notification_events']=[{'id':'one','acknowledged':False},{'id':'two','acknowledged':True}]
        unread=self.client.get('/api/mobile/v1/alerts?unread_only=1').json
        self.assertEqual([e['id'] for e in unread['events']],['one'])
        saved=copy.deepcopy(STATE['notification_settings']);history=copy.deepcopy(STATE['google_history'])
        no_csrf=self.client.post('/api/mobile/v1/action',json={'action':'clear_events'})
        self.assertEqual(no_csrf.status_code,403)
        r=self.client.post('/api/mobile/v1/action',json={'action':'acknowledge_all_events'},headers=self.headers)
        self.assertEqual(r.status_code,200)
        self.assertTrue(all(e['acknowledged'] for e in STATE['notification_events']))
        self.client.post('/api/mobile/v1/action',json={'action':'delete_event','event_id':'one'},headers=self.headers)
        self.assertEqual([e['id'] for e in STATE['notification_events']],['two'])
        self.client.post('/api/mobile/v1/action',json={'action':'clear_events'},headers=self.headers)
        self.assertEqual(STATE['notification_events'],[])
        self.assertEqual(json.loads((DATA/'notification_events.json').read_text()),[])
        self.assertEqual(STATE['notification_settings'],saved)
        self.assertEqual(STATE['google_history'],history)

    def issue(self,client_id):
        STATE['mcp_oauth']['clients'][client_id]={'client_name':client_id,'redirect_uris':['http://localhost/callback']}
        with APP.test_request_context(base_url='https://tracker.example'):
            tokens=M['mcp_issue_grant'](client_id,['trackers:read'],M['mcp_resource_url']())
            M['mcp_save_oauth']()
            return tokens

    def test_revoke_one_family_without_affecting_another(self):
        one=self.issue('one');two=self.issue('two')
        r=self.client.get('/api/mcp/settings')
        self.assertEqual(len(r.json['connections']),2)
        text=r.get_data(as_text=True)
        self.assertNotIn(one[0],text);self.assertNotIn(one[1],text)
        no_csrf=self.client.delete('/api/mcp/connections/'+one[2]['family'])
        self.assertEqual(no_csrf.status_code,403)
        r=self.client.delete('/api/mcp/connections/'+one[2]['family'],headers=self.headers)
        self.assertEqual(r.status_code,200)
        self.assertEqual(len(r.json['connections']),1)
        store=STATE['mcp_oauth']
        self.assertNotIn(M['mcp_hash_secret'](one[0]),store['access_tokens'])
        self.assertNotIn(M['mcp_hash_secret'](one[1]),store['refresh_tokens'])
        self.assertIn(M['mcp_hash_secret'](two[1]),store['refresh_tokens'])

    def test_disable_and_reenable_requires_new_oauth(self):
        self.issue('one')
        self.assertEqual(self.client.post('/api/mcp/settings',json={'enabled':False},headers=self.headers).status_code,200)
        self.assertEqual(self.client.post('/mcp',json={'jsonrpc':'2.0','id':1,'method':'initialize'}).status_code,503)
        self.assertEqual(STATE['mcp_oauth']['access_tokens'],{})
        self.assertEqual(self.client.post('/api/mcp/settings',json={'enabled':True},headers=self.headers).status_code,200)
        self.assertEqual(self.client.get('/api/mcp/settings').json['connections'],[])

    def test_admin_mcp_allowed_tracker_access_denied(self):
        with self.client.session_transaction() as s:s['admin_console']=True
        self.assertEqual(self.client.get('/api/mcp/settings').status_code,200)
        self.assertEqual(self.client.get('/api/mcp/diagnostics').status_code,200)
        self.assertEqual(self.client.get('/api/mobile/v1/trackers').status_code,403)

    def test_oauth_html_auth_and_pkce_exchange(self):
        public=APP.test_client()
        redirect='http://localhost/callback'
        reg=public.post('/oauth/register',json={'redirect_uris':[redirect],'client_name':'Regression ChatGPT'})
        self.assertEqual(reg.status_code,201,reg.json)
        verifier='a'*64;challenge=M['b64url_encode'](hashlib.sha256(verifier.encode()).digest())
        params={'client_id':reg.json['client_id'],'redirect_uri':redirect,'response_type':'code',
                'code_challenge':challenge,'code_challenge_method':'S256','scope':'trackers:read','resource':'https://tracker.example/mcp','state':'roundtrip'}
        page=public.get('/oauth/authorize',query_string=params)
        self.assertEqual(page.status_code,200,page.get_data(as_text=True))
        self.assertIn('Master- / Kontopasswort',page.get_data(as_text=True))
        transaction=html.unescape(re.search('name="transaction" value="([^"]+)"',page.get_data(as_text=True)).group(1))
        wrong=public.post('/oauth/authorize',data={'transaction':transaction,'password':'wrong'})
        self.assertEqual(wrong.status_code,403);self.assertEqual(wrong.mimetype,'text/html')
        self.assertIn('role="alert"',wrong.get_data(as_text=True))
        success=public.post('/oauth/authorize',data={'transaction':transaction,'password':'Regression-Test-Password'})
        self.assertEqual(success.status_code,302)
        callback=parse_qs(urlsplit(success.headers['Location']).query)
        self.assertEqual(callback['state'],['roundtrip'])
        token=public.post('/oauth/token',data={'grant_type':'authorization_code','client_id':reg.json['client_id'],
            'redirect_uri':redirect,'code':callback['code'][0],'code_verifier':verifier,'resource':params['resource']})
        self.assertEqual(token.status_code,200,token.json)
        self.assertIn('refresh_token',token.json)
        rpc=public.post('/mcp',json={'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25','clientInfo':{'name':'test','version':'1'},'capabilities':{}}},headers={'Authorization':'Bearer '+token.json['access_token']})
        self.assertEqual(rpc.status_code,200,rpc.json)
        self.assertIn('result',rpc.json)

if __name__=='__main__':unittest.main()
