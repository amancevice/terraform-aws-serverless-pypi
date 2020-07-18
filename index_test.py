import io
import json
import textwrap
from unittest import mock

import pytest

with mock.patch('boto3.client'):
    import index
    index.BASE_PATH = 'simple'
    index.S3_BUCKET = 'serverless-pypi'

SIMPLE_INDEX = (
    '<!DOCTYPE html><html><head><title>Simple index</title></head>'
    '<body><h1>Simple index</h1>'
    '<a href="fizz">fizz</a><br>'
    '<a href="buzz">buzz</a><br>'
    '</body></html>'
)

PACKAGE_INDEX = (
    '<!DOCTYPE html><html><head><title>Links for fizz</title></head>'
    '<body><h1>Links for fizz</h1>'
    '<a href="<presigned-url>">fizz-0.1.2.tar.gz</a><br>'
    '<a href="<presigned-url>">fizz-1.2.3.tar.gz</a><br>'
    '</body></html>'
)
S3_REINDEX_RESPONSE = [
    {'CommonPrefixes': [{'Prefix': 'fizz/'}, {'Prefix': 'buzz/'}]},
]
S3_INDEX_RESPONSE = [
    {
        'Contents': [
            {'Key': 'simple/fizz/fizz-0.1.2.tar.gz'},
            {'Key': 'simple/fizz/fizz-1.2.3.tar.gz'},
        ],
    },
]


def test_proxy_reponse():
    body = 'FIZZ'
    ret = index.proxy_reponse('FIZZ')
    exp = {
        'body': body,
        'statusCode': 200,
        'headers': {
            'Content-Size': len(body),
            'Content-Type': 'text/html; charset=UTF-8',
        },
    }
    assert ret == exp


def test_get_index():
    index.S3.get_object.return_value = {
        'Body': io.BytesIO(SIMPLE_INDEX.encode()),
    }
    ret = index.get_index()
    exp = {
        'body': SIMPLE_INDEX,
        'statusCode': 200,
        'headers': {
            'Content-Size': len(SIMPLE_INDEX),
            'Content-Type': 'text/html; charset=UTF-8',
        },
    }
    assert ret == exp


def test_get_package_index():
    index.S3.generate_presigned_url.return_value = "<presigned-url>"
    index.S3_PAGINATOR.paginate.return_value = iter(S3_INDEX_RESPONSE)
    ret = index.get_package_index('fizz')
    exp = {
        'body': PACKAGE_INDEX,
        'statusCode': 200,
        'headers': {
            'Content-Size': len(PACKAGE_INDEX),
            'Content-Type': 'text/html; charset=UTF-8',
        },
    }
    assert ret == exp


def test_get_package_index_fallback():
    index.FALLBACK_INDEX_URL = 'https://pypi.org/simple/'
    index.S3_PAGINATOR.paginate.return_value = iter([])
    ret = index.get_package_index('buzz')
    exp = {
        'statusCode': 301,
        'headers': {
            'Location': 'https://pypi.org/simple/buzz/',
        },
    }
    assert ret == exp


def test_get_package_index_not_found():
    index.FALLBACK_INDEX_URL = ''
    index.S3_PAGINATOR.paginate.return_value = iter([])
    body = json.dumps({'message': 'Not found'})
    ret = index.get_package_index('buzz')
    exp = {
        'body': body,
        'statusCode': 404,
        'headers': {
            'Content-Size': len(body),
            'Content-Type': 'application/json; charset=UTF-8',
        },
    }
    assert ret == exp


def test_redirect():
    ret = index.redirect('simple')
    exp = {'headers': {'Location': 'simple'}, 'statusCode': 301}
    assert ret == exp


def test_reject():
    body = json.dumps({'message': 'Unauthorized'})
    ret = index.reject(401, message='Unauthorized')
    exp = {
        'body': body,
        'statusCode': 401,
        'headers': {
            'Content-Size': len(body),
            'Content-Type': 'application/json; charset=UTF-8',
        },
    }
    assert ret == exp


def test_handler_get_root():
    event = {'httpMethod': 'GET', 'path': '/'}
    ret = index.proxy_request(event)
    exp = {
        'statusCode': 301,
        'headers': {
            'Location': '/simple/',
        },
    }
    assert ret == exp


@mock.patch('index.get_index')
def test_proxy_request_get(mock_idx):
    mock_idx.return_value = index.proxy_reponse(SIMPLE_INDEX)
    index.proxy_request({'httpMethod': 'GET', 'path': '/simple/'})
    mock_idx.assert_called_once_with()


@mock.patch('index.search')
def test_proxy_reponse_post(mock_search):
    mock_search.return_value = index.proxy_reponse('{}')
    index.proxy_request({
        'body': '<SEARCH_XML>',
        'httpMethod': 'POST',
        'path': '/simple/',
    })
    mock_search.assert_called_once_with('<SEARCH_XML>')


@mock.patch('index.get_package_index')
def test_proxy_request_get_package(mock_pkg):
    mock_pkg.return_value = index.proxy_reponse(PACKAGE_INDEX)
    index.proxy_request({'httpMethod': 'GET', 'path': '/simple/fizz/'})
    mock_pkg.assert_called_once_with('fizz')


@pytest.mark.parametrize('http_method,path,status_code', [
    ('HEAD', '/fizz/buzz/jazz', 403),
    ('GET', '/fizz/buzz/jazz', 403),
    ('POST', '/fizz/buzz/jazz', 403),
    ('OPTIONS', '/fizz/buzz/jazz', 403),
])
def test_proxy_request_reject(http_method, path, status_code):
    ret = index.proxy_request({'httpMethod': http_method, 'path': path})
    exp = index.reject(status_code, message='Forbidden')
    if http_method == 'HEAD':
        exp['body'] = ''
        exp['headers']['Content-Size'] = 0
    assert ret == exp


def test_reindex_bucket():
    index.S3_PAGINATOR.paginate.return_value = iter(S3_REINDEX_RESPONSE)
    index.reindex_bucket({})
    index.S3.put_object.assert_called_once_with(
        Bucket=index.S3_BUCKET,
        Key='index.html',
        Body=SIMPLE_INDEX.encode(),
    )


@pytest.mark.parametrize('pip', ['fizz'])
def test_search(pip):
    index.S3_PAGINATOR.paginate.return_value = iter(S3_INDEX_RESPONSE)
    request = textwrap.dedent(f'''\
        <?xml version='1.0'?>
        <methodCall>
        <methodName>search</methodName>
        <params>
        <param>
        <value><struct>
        <member>
        <name>name</name>
        <value><array><data>
        <value><string>{pip}</string></value>
        </data></array></value>
        </member>
        <member>
        <name>summary</name>
        <value><array><data>
        <value><string>{pip}</string></value>
        </data></array></value>
        </member>
        </struct></value>
        </param>
        <param>
        <value><string>or</string></value>
        </param>
        </params>
        </methodCall>\
    ''')
    body = (
        "<?xml version='1.0'?><methodResponse><params><param><value><array>"
        "<data><struct><member><name>name</name><value><string>fizz</string>"
        "</value></member><member><name>summary</name><value>"
        "<string>s3://serverless-pypi/simple/fizz/fizz-1.2.3.tar.gz</string>"
        "</value></member><member><name>version</name><value>"
        "<string>1.2.3</string></value></member><member>"
        "<name>_pypi_ordering</name><value><boolean>0</boolean></value>"
        "</member></struct></data></array></value></param></params>"
        "</methodResponse>"
    )
    ret = index.search(request)
    exp = {
        'body': body,
        'statusCode': 200,
        'headers': {
            'Content-Size': len(body),
            'Content-Type': 'text/xml; charset=UTF-8',
        },
    }
    assert ret == exp
