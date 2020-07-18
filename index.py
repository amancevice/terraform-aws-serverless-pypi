import json
import os
import string
import sys
from distutils.version import StrictVersion
from xml.etree import ElementTree as xml

import boto3

BASE_PATH = os.getenv('BASE_PATH', '').strip('/')
ANCHOR = string.Template('<a href="$href">$name</a><br>')
INDEX = string.Template(
    '<!DOCTYPE html><html><head><title>$title</title></head>'
    '<body><h1>$title</h1>$anchors</body></html>'
)
SEARCH = string.Template(
    "<?xml version='1.0'?>"
    '<methodResponse><params><param><value><array><data>'
    '$data'
    '</data></array></value></param></params></methodResponse>'
)
SEARCH_VALUE = string.Template(
    '<struct>'
    '<member><name>name</name><value><string>'
    '$name'
    '</string></value></member>'
    '<member><name>summary</name><value><string>'
    '$summary'
    '</string></value></member>'
    '<member><name>version</name><value><string>'
    '$version'
    '</string></value></member>'
    '<member><name>_pypi_ordering</name><value><boolean>'
    '0'
    '</boolean></value></member>'
    '</struct>'
)

S3 = boto3.client('s3')
S3_BUCKET = os.getenv('S3_BUCKET', 'serverless-pypi')
S3_PAGINATOR = S3.get_paginator('list_objects')
S3_PRESIGNED_URL_TTL = int(os.getenv('S3_PRESIGNED_URL_TTL', '900'))

FALLBACK_INDEX_URL = os.getenv('FALLBACK_INDEX_URL')


# Lambda helpers

def get_index():
    """
    GET /{BASE_PATH}/

    :return dict: Response
    """
    index = S3.get_object(Bucket=S3_BUCKET, Key='index.html')
    body = index['Body'].read().decode()
    return proxy_reponse(body)


def get_package_index(name):
    """
    GET /{BASE_PATH}/<pkg>/

    :param str name: Package name
    :return dict: Response
    """
    # Get keys for given package
    pages = S3_PAGINATOR.paginate(Bucket=S3_BUCKET, Prefix=f'{name}/')
    keys = [
        key.get('Key')
        for page in pages
        for key in page.get('Contents') or []
    ]

    # Go to fallback index if no keys
    if FALLBACK_INDEX_URL and not any(keys):
        fallback_url = os.path.join(FALLBACK_INDEX_URL, name, '')
        return redirect(fallback_url)

    # Respond with 404 if no keys and no fallback index
    elif not any(keys):
        return reject(404, message='Not found')

    # Convert keys to presigned URLs
    hrefs = [presign(key) for key in keys]

    # Extract names of packages from keys
    names = [os.path.split(x)[-1] for x in keys]

    # Construct HTML
    anchors = [
        ANCHOR.safe_substitute(href=href, name=name)
        for href, name in zip(hrefs, names)
    ]
    body = INDEX.safe_substitute(
        title=f'Links for {name}',
        anchors=''.join(anchors)
    )

    # Convert to Lambda proxy response
    return proxy_reponse(body)


def get_response(path, *_):
    """
    GET /{BASE_PATH}/*

    :param str path: Request path
    :return dict: Response
    """
    # GET /
    if not path and BASE_PATH:
        return redirect(f'/{BASE_PATH}/')

    # GET /{BASE_PATH}/
    if path == BASE_PATH:
        return get_index()

    # GET /{BASE_PATH}/*
    elif path.startswith(BASE_PATH):
        return get_package_index(os.path.basename(path))

    # 403 Forbidden
    return reject(403, message='Forbidden')


def head_response(path, *_):
    """
    HEAD /{BASE_PATH}/*

    :param str path: Request path
    :return dict: Response
    """
    res = get_response(path)
    res['body'] = ''
    res['headers']['Content-Length'] = 0
    return res


def post_response(path, body):
    """
    POST /{BASE_PATH}/

    :param str path: POST path
    :param str body: POST body
    :return dict: Response
    """
    if path == BASE_PATH:
        return search(body)

    return reject(403, message='Forbidden')


def presign(key):
    """
    Presign package URLs.

    :param str key: S3 key to presign
    :return str: Presigned URL
    """
    url = S3.generate_presigned_url(
        'get_object',
        ExpiresIn=S3_PRESIGNED_URL_TTL,
        HttpMethod='GET',
        Params=dict(Bucket=S3_BUCKET, Key=key),
    )
    return url


def proxy_reponse(body, content_type=None):
    """
    Convert HTML to API Gateway response.

    :param str body: HTML body
    :return dict: API Gateway Lambda proxy response
    """
    content_type = content_type or 'text/html'
    # Wrap HTML in proxy response object
    res = {
        'body': body,
        'statusCode': 200,
        'headers': {
            'Content-Length': len(body),
            'Content-Type': f'{content_type}; charset=UTF-8',
        },
    }
    return res


def redirect(path):
    """
    Redirect requests.

    :param str path: Rejection status code
    :return dict: Redirection response
    """
    return dict(statusCode=301, headers={'Location': path})


def reject(status_code, **kwargs):
    """
    Bad request.

    :param int status_code: Rejection status code
    :param dict kwargs: Rejection body JSON
    :return dict: Rejection response
    """
    body = json.dumps(kwargs) if kwargs else ''
    headers = {
        'Content-Length': len(body),
        'Content-Type': 'application/json; charset=UTF-8',
    }
    return dict(body=body, headers=headers, statusCode=status_code)


def search(request):
    """
    Search for pips.

    :param str request: XML request string
    :return str: XML response
    """
    tree = xml.fromstring(request)
    term = tree.find('.//string').text  # TODO this is not ideal

    hits = {}
    for page in S3_PAGINATOR.paginate(Bucket=S3_BUCKET):
        for obj in page.get('Contents'):
            key = obj.get('Key')
            if term in key and 'index.html' != key:
                *_, name, tarball = key.split('/')
                _, version = tarball.replace('.tar.gz', '').split(f'{name}-')
                version = StrictVersion(version)
                if name not in hits or hits[name]['version'] < version:
                    hits[name] = dict(
                        name=name,
                        version=version,
                        summary=f's3://{S3_BUCKET}/{key}',
                    )
    data = [SEARCH_VALUE.safe_substitute(**x) for x in hits.values()]
    body = SEARCH.safe_substitute(data=''.join(data))
    resp = proxy_reponse(body, 'text/xml')
    return resp


# Lambda handlers

ROUTES = dict(GET=get_response, HEAD=head_response, POST=post_response)


def proxy_request(event, *_):
    """
    Handle API Gateway proxy request.
    """
    print(f'EVENT {json.dumps(event)}')
    print(f'BASE_PATH {BASE_PATH!r}')

    # Get HTTP request method/path
    method = event.get('httpMethod')
    path = event.get('path').strip('/')
    body = event.get('body')

    # Get HTTP response
    try:
        res = ROUTES[method](path, body)
    except KeyError:
        res = reject(403, message='Forbidden')

    # Return proxy response
    statusCode = res['statusCode']
    print(f'RESPONSE [{statusCode}] {json.dumps(res)}')
    return res


def reindex_bucket(event, *_):
    """
    Reindex S3 bucket.
    """
    print(f'EVENT {json.dumps(event)}')

    # Get package names from common prefixes
    pages = S3_PAGINATOR.paginate(Bucket=S3_BUCKET, Delimiter='/')
    pkgs = (
        x.get('Prefix').strip('/')
        for page in pages
        for x in page.get('CommonPrefixes')
    )

    # Construct HTML
    anchors = (ANCHOR.safe_substitute(href=pkg, name=pkg) for pkg in pkgs)
    body = INDEX.safe_substitute(
        title='Simple index',
        anchors=''.join(anchors)
    )

    # Upload to S3 as index.html
    res = S3.put_object(Bucket=S3_BUCKET, Key='index.html', Body=body.encode())
    return res


if __name__ == '__main__':  # pragma: no cover
    try:
        path = sys.argv[1]
        event = dict(path=path, httpMethod='GET')
    except IndexError:
        this = os.path.basename(__file__)
        raise SystemExit(f'usage: python {this} <url-path>')
    proxy_request(event)
