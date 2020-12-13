import io
import json
import os
import textwrap
from unittest import mock

import pytest

os.environ['BASE_PATH'] = 'simple'
os.environ['S3_BUCKET'] = 'serverless-pypi'

with mock.patch('boto3.client'):
    import index

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
            'Content-Length': len(body),
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
            'Content-Length': len(SIMPLE_INDEX),
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
            'Content-Length': len(PACKAGE_INDEX),
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
            'Content-Length': len(body),
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
            'Content-Length': len(body),
            'Content-Type': 'application/json; charset=UTF-8',
        },
    }
    assert ret == exp


@pytest.mark.parametrize(('event', 'exp'), [
    (
        {
            'version': '1.0',
            'httpMethod': 'GET',
            'path': '/simple',
        },
        {
            'statusCode': 301,
            'headers': {
                'Location': '/simple/',
            },
        }
    ),
    (
        {
            'version': '2.0',
            'requestContext': {
                'http': {
                    'method': 'GET',
                    'path': '/simple',
                },
            },
        },
        {
            'statusCode': 301,
            'headers': {
                'Location': '/simple/',
            },
        }
    ),
    (
        {
            'version': '1.0',
            'httpMethod': 'GET',
            'path': '/',
        },
        {
            'statusCode': 403,
            'body': json.dumps({'message': 'Forbidden'}),
            'headers': {
                'Content-Length': 24,
                'Content-Type': 'application/json; charset=UTF-8',
            },
        }
    ),
    (
        {
            'version': '2.0',
            'requestContext': {
                'http': {
                    'method': 'GET',
                    'path': '/',
                },
            },
        },
        {
            'statusCode': 403,
            'body': json.dumps({'message': 'Forbidden'}),
            'headers': {
                'Content-Length': 24,
                'Content-Type': 'application/json; charset=UTF-8',
            },
        }
    ),
])
def test_handler_get_root(event, exp):
    ret = index.proxy_request(event)
    assert ret == exp


@pytest.mark.parametrize('event', [
    {
        'version': '1.0',
        'httpMethod': 'GET',
        'path': '/simple/',
    },
    {
        'version': '2.0',
        'requestContext': {
            'http': {
                'method': 'GET',
                'path': '/simple/',
            },
        },
    },
])
def test_proxy_request_get(event):
    with mock.patch('index.get_index') as mock_idx:
        mock_idx.return_value = index.proxy_reponse(SIMPLE_INDEX)
        index.proxy_request(event)
        mock_idx.assert_called_once_with()


@pytest.mark.parametrize('event', [
    {
        'version': '1.0',
        'body': '<SEARCH_XML>',
        'httpMethod': 'POST',
        'path': '/simple/',
    },
    {
        'version': '2.0',
        'body': '<SEARCH_XML>',
        'requestContext': {
            'http': {
                'method': 'POST',
                'path': '/simple/',
            },
        },
    },
])
def test_proxy_reponse_post(event):
    with mock.patch('index.search') as mock_search:
        mock_search.return_value = index.proxy_reponse('{}')
        index.proxy_request(event)
        mock_search.assert_called_once_with('<SEARCH_XML>')


@pytest.mark.parametrize('event', [
    {
        'version': '1.0',
        'httpMethod': 'GET',
        'path': '/simple/fizz/'
    },
    {
        'version': '2.0',
        'requestContext': {
            'http': {
                'method': 'GET',
                'path': '/simple/fizz/',
            },
        },
    },
])
def test_proxy_request_get_package(event):
    with mock.patch('index.get_package_index') as mock_pkg:
        mock_pkg.return_value = index.proxy_reponse(PACKAGE_INDEX)
        index.proxy_request(event)
        mock_pkg.assert_called_once_with('fizz')


@pytest.mark.parametrize(('version', 'http_method', 'path', 'status_code'), [
    ('1.0', 'HEAD', '/fizz/buzz/jazz', 403),
    ('1.0', 'GET', '/fizz/buzz/jazz', 403),
    ('1.0', 'POST', '/fizz/buzz/jazz', 403),
    ('1.0', 'OPTIONS', '/fizz/buzz/jazz', 403),
    ('2.0', 'HEAD', '/fizz/buzz/jazz', 403),
    ('2.0', 'GET', '/fizz/buzz/jazz', 403),
    ('2.0', 'POST', '/fizz/buzz/jazz', 403),
    ('2.0', 'OPTIONS', '/fizz/buzz/jazz', 403),
])
def test_proxy_request_reject(version, http_method, path, status_code):
    event = dict(version=version)
    if version == '1.0':
        event.update(httpMethod=http_method, path=path)
    else:
        event.update(requestContext=dict(http=dict(
            method=http_method,
            path=path,
        )))
    ret = index.proxy_request(event)
    exp = index.reject(status_code, message='Forbidden')
    if http_method == 'HEAD':
        exp['body'] = ''
        exp['headers']['Content-Length'] = 0
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
            'Content-Length': len(body),
            'Content-Type': 'text/xml; charset=UTF-8',
        },
    }
    assert ret == exp
