"""Anisette V2 bridge for the verified iTunes 4.19 CoreADI build.

A fresh emulator per OTP prevents the upstream long-lived VM exhaustion.
Only provisioning keeps a VM across start/end; account state embeds the
machine UUID and ADI files, allowing restart without a fresh registration.
"""
import asyncio
import base64
import json
import os
from pathlib import Path
from threading import RLock
import uuid

from anisette._adi import BaseADI, CPIM, OneTimePassword
from apple_coreadi.adi_run import CoreADI

STORE = '/Users/Shared/adi/'


def signed(value):
    return value - (1 << 64) if value >= 1 << 63 else value


def checked(result):
    if not result.ok:
        raise RuntimeError(f'Apple CoreADI {result.name} failed ({result.rc}/{result.ret})')
    return result.outputs


class ITunesADI(BaseADI):
    def __init__(self, identifier, adi_pb):
        self.identifier = identifier
        self.lock = RLock()
        self.pending = None
        self.files = {}
        self.host_uuid = uuid.uuid4().bytes
        self.routing = None
        if adi_pb:
            data = json.loads(adi_pb)
            if data.get('provider') != 'itunes-coreadi' or data.get('version') != 1 or data.get('identifier') != identifier:
                raise ValueError('Apple ADI session requires a new Apple login')
            self.host_uuid = bytes.fromhex(data['host_uuid'])
            if len(self.host_uuid) != 16:
                raise ValueError('Invalid Apple ADI machine UUID')
            self.files = {key: base64.b64decode(value, validate=True) for key, value in data['files'].items() if key.startswith(STORE) and key != STORE+'adi.pb'}
            self.routing = data.get('routing')

    @classmethod
    def create(cls, url=None):
        if url is not None:
            raise ValueError('Use setup_apple_adi.py for the official Apple runtime')
        return lambda identifier, adi_pb: cls(identifier, adi_pb)

    @property
    def routing_information(self):
        return self.routing

    @property
    def adi_pb(self):
        with self.lock:
            return json.dumps({'provider': 'itunes-coreadi', 'version': 1,
                'identifier': self.identifier, 'host_uuid': self.host_uuid.hex(),
                'routing': self.routing,
                'files': {k: base64.b64encode(v).decode() for k,v in self.files.items()}}, sort_keys=True).encode()

    def _core(self):
        core = CoreADI(Path(os.environ['MACOS_ADI_BINARY']))
        core.stubs.hostuuid = self.host_uuid
        core.stubs.files.update({k: bytearray(v) for k,v in self.files.items()})
        checked(core.initialize())
        return core

    def _save(self, core):
        self.files = {k: bytes(v) for k,v in core.stubs.files.items() if k.startswith(STORE) and k != STORE+'adi.pb'}

    async def _run(self, operation):
        def call():
            with self.lock:
                return operation()
        return await asyncio.get_running_loop().run_in_executor(None, call)

    async def is_machine_provisioned(self, ds_id=(1 << 64)-2):
        def call():
            result = self._core().is_machine_provisioned(signed(ds_id))
            if result.ret == -45061:
                return False
            checked(result)
            return True
        return await self._run(call)

    async def start_provisioning(self, spim, ds_id=(1 << 64)-2):
        def call():
            self.pending = self._core()
            result = checked(self.pending.provisioning_start(signed(ds_id), spim))
            return CPIM(result['cpim'], result['session_id'])
        return await self._run(call)

    async def end_provisioning(self, session, persistent_token_metadata, trust_key):
        def call():
            if self.pending is None:
                raise RuntimeError('No pending Apple ADI provisioning session')
            try:
                checked(self.pending.provisioning_end(session, persistent_token_metadata, trust_key))
                self._save(self.pending)
            finally:
                self.pending = None
        await self._run(call)

    async def set_idms_routing(self, routing_information):
        def call():
            core = self._core()
            checked(core.set_routing(-2, routing_information))
            self.routing = routing_information
            self._save(core)
        await self._run(call)

    async def request_otp(self, ds_id=(1 << 64)-2):
        def call():
            core = self._core()
            result = checked(core.request_otp(signed(ds_id)))
            self._save(core)
            return OneTimePassword(otp=result['otp'], machine_id=result['mid'])
        return await self._run(call)


def install_itunes_adi_backend():
    from anisette import AsyncAnisetteProvider
    AsyncAnisetteProvider.DEFAULT_ADI = ITunesADI
