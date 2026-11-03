"""Pinned AP2 SDK + Schema interoperability, offline; synthetic keys stay in RAM."""
import base64
import hashlib
import json
import sys
from pathlib import Path
from unittest.mock import patch
from ap2.sdk.mandate import MandateClient
from ap2.sdk.generated.payment_mandate import PaymentMandate
from ap2.sdk.generated.open_payment_mandate import OpenPaymentMandate
from ap2.sdk.generated.payment_receipt import PaymentReceipt
from ap2.sdk.payment_mandate_chain import PaymentMandateChain
from ap2.sdk.disclosure_metadata import DisclosureMetadata
from ap2.sdk.sdjwt import sd_jwt, kb_sd_jwt, chain as sdk_chain
from ap2.sdk.sdjwt.common import parse_token, compute_sd_hash
from ap2.sdk.jwt_helper import create_jwt, verify_jwt
from jwcrypto.jwk import JWK
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

NOW = 1800000000
root = Path('/official')
assert Path(sd_jwt.__file__).resolve().is_relative_to(root), 'unexpected SDK'
def digest(wire):
    return base64.urlsafe_b64encode(hashlib.sha256(wire.encode('ascii')).digest()).decode().rstrip('=')
def claims(wire):
    p = wire.split('.')[1]
    return json.loads(base64.urlsafe_b64decode(p + '=' * (-len(p) % 4)))
def no_remote(uri):
    raise ValueError('unregistered reference: ' + uri)
registry = Registry(retrieve=no_remote)
schemas = root/'code/sdk/schemas'
for path in schemas.rglob('*.json'):
    content = json.loads(path.read_text())
    registry = registry.with_resource(content['$id'], Resource.from_contents(content))
# Official Receipt status file has an inconsistent $id; resolve its known local URI.
registry = registry.with_resource('https://ap2-protocol.org/schemas/types/receipt_status.json',
    Resource.from_contents(json.loads((schemas/'ap2/types/receipt_status.json').read_text())))
def schema(name, value):
    Draft202012Validator(json.loads((schemas/'ap2'/name).read_text()), registry=registry).validate(value)

source = json.loads(Path(sys.argv[1]).read_text())
client = MandateClient()
for mode in ['direct', 'conditional']:
    args = source[mode]
    wire = args['closed_sd_jwt']
    provider = JWK.from_pem(args['trusted_provider_public_key_pem'].encode())
    expected = dict(args['expected_payment'], vct='mandate.payment.1', iat=NOW, exp=NOW+60)
    if mode == 'direct':
        result = client.verify(wire, provider, payload_type=PaymentMandate, current_time=NOW, clock_skew_seconds=0)
        assert result.mandate_payload.model_dump(exclude_none=True) == expected
    else:
        chain = args['open_sd_jwt'].removesuffix('~') + '~~' + wire
        payloads = sdk_chain.verify_chain([parse_token(args['open_sd_jwt']), parse_token(wire)], lambda _: provider, expected_aud=args['expected_audience'],
            expected_nonce=args['expected_nonce'], current_time=NOW, clock_skew_seconds=0)
        assert client.verify(chain, lambda _: provider, expected_aud=args['expected_audience'], expected_nonce=args['expected_nonce'], current_time=NOW, clock_skew_seconds=0) == payloads
        assert payloads[1] == expected
        typed = PaymentMandateChain.parse(payloads)
        assert typed.verify(expected_transaction_id=digest(args['checkout_inputs']['host_checkout_jws']),
            expected_open_checkout_hash=digest(args['checkout_inputs']['root_presentation'])) == []
        schema('open_payment_mandate.json', payloads[0])
        for field in ['payment_amount', 'payee', 'payment_instrument']:
            changed = json.loads(json.dumps(payloads))
            if field == 'payment_amount': changed[1][field]['amount'] += 1
            else: changed[1][field]['id'] = 'other'
            assert PaymentMandateChain.parse(changed).verify(expected_open_checkout_hash=digest(args['checkout_inputs']['root_presentation']))
    schema('payment_mandate.json', expected)
    assert compute_sd_hash(parse_token(wire)) == digest(wire)
for args in source['receipts']:
    value = verify_jwt(args['jwt'], JWK.from_pem(args['trusted_public_key_pem'].encode()))
    PaymentReceipt.model_validate(value)
    schema('payment_receipt.json', value)
    assert value['reference'] == digest(args['closed_sd_jwt']) and value['iss'] == args['expected_issuer']

# Official SDK issues a second set under fresh Python keys; no Ruby signer used.
provider = JWK.generate(kty='EC', crv='P-256')
agent = JWK.generate(kty='EC', crv='P-256')
pub_agent = {k:v for k,v in agent.export_public(as_dict=True).items() if k in ['kty','crv','x','y']}
output = {}
for mode in ['direct', 'conditional']:
    args = source[mode]
    args['trusted_provider_public_key_pem'] = provider.export_to_pem().decode()
    value = PaymentMandate.model_validate(dict(args['expected_payment'], vct='mandate.payment.1', iat=NOW, exp=NOW+60))
    if mode == 'direct':
        args['closed_sd_jwt'] = client.create([value], provider, sd=DisclosureMetadata())
    else:
        content = dict(source['open_content'], cnf={'jwk': pub_agent})
        opening = client.create([OpenPaymentMandate.model_validate(content)], provider, sd=DisclosureMetadata())
        # SDK uses wall time at signing; freeze it for a reproducible explicit clock.
        with patch('ap2.sdk.sdjwt.kb_sd_jwt.time.time', return_value=NOW):
            issued = kb_sd_jwt.create(parse_token(opening), agent, value,
                aud=args['expected_audience'], nonce=args['expected_nonce'], sd=DisclosureMetadata())
        args['open_sd_jwt'] = opening
        args['closed_sd_jwt'] = issued.sd_jwt_issuance
        args['expected_agent_public_key_pem'] = agent.export_to_pem().decode()
    output[mode] = args
output['receipts'] = []
for args in source['receipts']:
    value = claims(args['jwt'])
    # Bind each Python Receipt to corresponding Python-issued final Payment.
    mode = 'conditional' if 'sd_hash' in claims(args['closed_sd_jwt']) else 'direct'
    args['closed_sd_jwt'] = output[mode]['closed_sd_jwt']
    value['reference'] = digest(args['closed_sd_jwt'])
    args['jwt'] = create_jwt({'alg':'ES256','typ':'JWT'}, value, provider)
    args['trusted_public_key_pem'] = provider.export_to_pem().decode()
    output['receipts'].append(args)
Path(sys.argv[2]).write_text(json.dumps(output))
print('PASS Ruby->official Python SDK: Direct, conditional full chain/constraints, four Receipts; Schema and independent original-wire hashes')
print('Python SDK->Ruby fixture issued with independent in-memory Python keys')
