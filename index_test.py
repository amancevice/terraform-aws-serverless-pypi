import io
from unittest import mock

import pytest

with mock.patch('boto3.client'):
    import index
    index.BASE_PATH = 'simple'

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
    ret = index.proxy_reponse('FIZZ')
    exp = {
        'body': 'FIZZ',
        'headers': {'Content-Type': 'text/html; charset=UTF-8'},
        'statusCode': 200,
    }
    assert ret == exp


def test_get_index():
    index.S3.get_object.return_value = {
        'Body': io.BytesIO(SIMPLE_INDEX.encode()),
    }
    ret = index.get_index()
    exp = {
        'body': SIMPLE_INDEX,
        'headers': {'Content-Type': 'text/html; charset=UTF-8'},
        'statusCode': 200,
    }
    assert ret == exp


def test_get_package_index():
    index.S3.generate_presigned_url.return_value = "<presigned-url>"
    index.S3_PAGINATOR.paginate.return_value = iter(S3_INDEX_RESPONSE)
    ret = index.get_package_index('fizz')
    exp = {
        'body': PACKAGE_INDEX,
        'headers': {'Content-Type': 'text/html; charset=UTF-8'},
        'statusCode': 200,
    }
    assert ret == exp


def test_redirect():
    ret = index.redirect('simple')
    exp = {'headers': {'Location': 'simple'}, 'statusCode': 301}
    assert ret == exp


def test_reject():
    ret = index.reject(401)
    exp = {'statusCode': 401}
    assert ret == exp


def test_handler_get_root():
    event = {'httpMethod': 'GET', 'path': '/'}
    ret = index.proxy_request(event)
    exp = {
        'statusCode': 301,
        'headers': {
            'Location': '/simple',
        },
    }
    assert ret == exp


@mock.patch('index.get_index')
def test_proxy_request_get(mock_idx):
    mock_idx.return_value = index.proxy_reponse(SIMPLE_INDEX)
    index.proxy_request({'httpMethod': 'GET', 'path': '/simple/'})
    mock_idx.assert_called_once_with()


@mock.patch('index.get_package_index')
def test_proxy_request_get_package(mock_pkg):
    mock_pkg.return_value = index.proxy_reponse(PACKAGE_INDEX)
    index.proxy_request({'httpMethod': 'GET', 'path': '/simple/fizz/'})
    mock_pkg.assert_called_once_with('fizz')


@pytest.mark.parametrize('http_method,path,status_code', [
    ('GET', '/fizz/buzz/jazz', 403),
    ('POST', '/fizz/buzz', 403),
])
def test_proxy_request_reject(http_method, path, status_code):
    ret = index.proxy_request({'httpMethod': http_method, 'path': path})
    exp = index.reject(status_code)
    assert ret == exp


def test_reindex_bucket():
    index.S3_PAGINATOR.paginate.return_value = iter(S3_REINDEX_RESPONSE)
    index.reindex_bucket({})
    index.S3.put_object.assert_called_once_with(
        Bucket=index.S3_BUCKET,
        Key='index.html',
        Body=SIMPLE_INDEX.encode(),
    )
