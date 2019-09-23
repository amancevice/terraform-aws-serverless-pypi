import io
import textwrap
from unittest import mock

with mock.patch('boto3.client'):
    import index

SIMPLE_INDEX = textwrap.dedent('''\
  <!DOCTYPE html>
  <html>
  <head>
    <title>Simple index</title>
  </head>
  <body>
    <h1>Simple index</h1>
    <a href="fizz">fizz</a><br>
    <a href="buzz">buzz</a><br>
  </body>
  </html>
''')

PACKAGE_INDEX = textwrap.dedent('''\
  <!DOCTYPE html>
  <html>
  <head>
    <title>Links for fizz</title>
  </head>
  <body>
    <h1>Links for fizz</h1>
    <a href="<presigned-url>">fizz-0.1.2.tar.gz</a><br>
    <a href="<presigned-url>">fizz-1.2.3.tar.gz</a><br>
  </body>
  </html>
''')


def test_proxy_reponse():
    ret = index.proxy_reponse('FIZZ')
    exp = {
        'body': 'FIZZ',
        'headers': {'Content-Type': 'text/html'},
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
        'headers': {'Content-Type': 'text/html'},
        'statusCode': 200,
    }
    assert ret == exp


def test_get_package_index():
    index.S3.generate_presigned_url.return_value = "<presigned-url>"
    index.S3_PAGINATOR.paginate.return_value = iter([
        {
            'Contents': [
                {'Key': 'simple/fizz/fizz-0.1.2.tar.gz'},
                {'Key': 'simple/fizz/fizz-1.2.3.tar.gz'},
            ],
        },
    ])
    ret = index.get_package_index('fizz')
    exp = {
        'body': PACKAGE_INDEX,
        'headers': {'Content-Type': 'text/html'},
        'statusCode': 200,
    }
    assert ret == exp


def test_redirect():
    ret = index.redirect('simple')
    exp = {'headers': {'Location': 'simple'}, 'statusCode': 301}
    assert ret == exp


def test_forbidden():
    ret = index.forbidden()
    exp = {'statusCode': 403}
    assert ret == exp


def test_handler_root():
    event = {'path': '/'}
    ret = index.handler(event)
    exp = {'headers': {'Location': 'simple'}, 'statusCode': 301}
    assert ret == exp


@mock.patch('index.get_index')
def test_handler_simple(mock_idx):
    mock_idx.return_value = index.proxy_reponse(SIMPLE_INDEX)
    index.handler({'path': '/simple/'})
    mock_idx.assert_called_once_with()


@mock.patch('index.get_package_index')
def test_handler_package(mock_idx):
    mock_idx.return_value = index.proxy_reponse(PACKAGE_INDEX)
    index.handler({'path': '/simple/fizz/'})
    mock_idx.assert_called_once_with('fizz')


@mock.patch('index.forbidden')
def test_handler_forbidden(mock_403):
    mock_403.return_value = {'statusCode': 403}
    index.handler({'path': '/simple/fizz/buzz/jazz'})
    mock_403.assert_called_once_with()


def test_reindex():
    index.S3_PAGINATOR.paginate.return_value = iter([
        {'CommonPrefixes': [{'Prefix': 'fizz/'}, {'Prefix': 'buzz/'}]},
    ])
    index.reindex({})
    index.S3.put_object.assert_called_once_with(
        Bucket=index.S3_BUCKET,
        Key='index.html',
        Body=SIMPLE_INDEX.encode(),
    )
