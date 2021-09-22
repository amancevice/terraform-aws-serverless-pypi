import io
import json
import os
import re
from unittest import mock

import pytest

os.environ['S3_BUCKET'] = 'serverless-pypi'

with mock.patch('boto3.client'):
    import index
    from index import (ANCHOR, INDEX, SEARCH, SEARCH_VALUE)

SIMPLE_INDEX = INDEX.safe_substitute(
    title='Simple index',
    anchors=str.join('', [
        ANCHOR.safe_substitute(href='fizz', name='fizz'),
        ANCHOR.safe_substitute(href='buzz', name='buzz'),
    ]),
)
PACKAGE_INDEX = INDEX.safe_substitute(
    title='Links for fizz',
    anchors=str.join('', [
        ANCHOR.safe_substitute(href='presigned-url', name='fizz-0.1.2.tar.gz'),
        ANCHOR.safe_substitute(href='presigned-url', name='fizz-1.2.3.tar.gz'),
    ]),
)
S3_REINDEX_RESPONSE = [
    {'CommonPrefixes': [{'Prefix': 'fizz/'}, {'Prefix': 'buzz/'}]},
]
S3_INDEX_RESPONSE = [
    {
        'Contents': [
            {'Key': 'fizz/fizz-0.1.2.tar.gz'},
            {'Key': 'fizz/fizz-1.2.3.tar.gz'},
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
            'content-length': len(body),
            'content-type': 'text/html; charset=utf-8',
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
            'content-length': len(SIMPLE_INDEX),
            'content-type': 'text/html; charset=utf-8',
        },
    }
    assert ret == exp


def test_get_package_index():
    index.S3.generate_presigned_url.return_value = 'presigned-url'
    index.S3_PAGINATOR.paginate.return_value = iter(S3_INDEX_RESPONSE)
    ret = index.get_package_index('fizz')
    exp = {
        'body': PACKAGE_INDEX,
        'statusCode': 200,
        'headers': {
            'content-length': len(PACKAGE_INDEX),
            'content-type': 'text/html; charset=utf-8',
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
    body = json.dumps({'message': 'Not Found'})
    ret = index.get_package_index('buzz')
    exp = {
        'body': body,
        'statusCode': 404,
        'headers': {
            'content-length': len(body),
            'content-type': 'application/json; charset=utf-8',
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
            'content-length': len(body),
            'content-type': 'application/json; charset=utf-8',
        },
    }
    assert ret == exp


@pytest.mark.parametrize(('event', 'exp'), [
    (
        {'version': '2.0', 'routeKey': 'GET /'},
        {
            'statusCode': 200,
            'body': '',
            'headers': {
                'content-length': 0,
                'content-type': 'text/html; charset=utf-8',
            },
        }
    ),
])
def test_handler_get_root(event, exp):
    ret = index.proxy_request(event)
    assert ret == exp


@pytest.mark.parametrize('event', [
    {'version': '2.0', 'routeKey': 'GET /'},
    {'version': '2.0', 'routeKey': 'HEAD /'},
    {'httpMethod': 'GET'},
    {'httpMethod': 'HEAD'},
])
def test_proxy_request_get(event):
    with mock.patch('index.get_index') as mock_idx:
        mock_idx.return_value = index.proxy_reponse(SIMPLE_INDEX)
        index.proxy_request(event)
        mock_idx.assert_called_once_with()


@pytest.mark.parametrize('event', [
    {'version': '2.0', 'routeKey': 'POST /', 'body': '<SEARCH_XML>'},
    {'httpMethod': 'POST', 'body': '<SEARCH_XML>'},
])
def test_proxy_reponse_post(event):
    with mock.patch('index.search') as mock_search:
        mock_search.return_value = index.proxy_reponse('{}')
        index.proxy_request(event)
        mock_search.assert_called_once_with('<SEARCH_XML>')


@pytest.mark.parametrize('event', [
    {
        'version': '2.0',
        'routeKey': 'GET /fizz',
        'pathParameters': {'package': 'fizz'}
    },
    {
        'httpMethod': 'GET',
        'pathParameters': {'package': 'fizz'}
    }
])
def test_proxy_request_get_package(event):
    with mock.patch('index.get_package_index') as mock_pkg:
        mock_pkg.return_value = index.proxy_reponse(PACKAGE_INDEX)
        index.proxy_request(event)
        mock_pkg.assert_called_once_with('fizz')


@pytest.mark.parametrize(('event', 'status_code', 'msg'), [
    (
        {
            'version': '2.0',
            'routeKey': 'OPTIONS /fizz',
            'pathParameters': {'package': 'fizz'}
        },
        403, 'Forbidden',
    ),
    (
        {
            'version': '2.0',
            'routeKey': 'POST /fizz',
            'pathParameters': {'package': 'fizz'}
        },
        403, 'Forbidden',
    ),
])
def test_proxy_request_reject(event, status_code, msg):
    ret = index.proxy_request(event)
    exp = index.reject(status_code, message=msg)
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
    request = re.sub(r'\n *', '', f'''
        <?xml version='1.0'?>
        <methodCall>
          <methodName>search</methodName>
          <params>
            <param>
              <value>
                <struct>
                  <member>
                    <name>name</name>
                    <value>
                      <array>
                        <data>
                          <value>
                            <string>{pip}</string>
                          </value>
                        </data>
                      </array>
                    </value>
                  </member>
                  <member>
                    <name>summary</name>
                    <value>
                      <array>
                        <data>
                          <value>
                            <string>{pip}</string>
                          </value>
                        </data>
                      </array>
                    </value>
                  </member>
                </struct>
              </value>
            </param>
            <param>
              <value>
                <string>or</string>
              </value>
            </param>
          </params>
        </methodCall>
    ''')
    body = SEARCH.safe_substitute(data=SEARCH_VALUE.safe_substitute(
        name='fizz',
        summary='s3://serverless-pypi/fizz/fizz-1.2.3.tar.gz',
        version='1.2.3',
    ))
    ret = index.search(request)
    exp = {
        'body': body,
        'statusCode': 200,
        'headers': {
            'content-length': len(body),
            'content-type': 'text/xml; charset=utf-8',
        },
    }
    assert ret == exp
