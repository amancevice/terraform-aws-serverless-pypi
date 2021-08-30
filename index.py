import json
import logging
import os
import re
from string import Template
from distutils.version import StrictVersion
from xml.etree import ElementTree as xml

import boto3

S3 = boto3.client('s3')
S3_BUCKET = os.environ['S3_BUCKET']
S3_PAGINATOR = S3.get_paginator('list_objects')
S3_PRESIGNED_URL_TTL = int(os.getenv('S3_PRESIGNED_URL_TTL', '900'))

FALLBACK_INDEX_URL = os.getenv('FALLBACK_INDEX_URL')
LOG_LEVEL = os.getenv('LOG_LEVEL') or 'INFO'
LOG_FORMAT = os.getenv('LOG_FORMAT') or '%(levelname)s %(reqid)s %(message)s'


class SuppressFilter(logging.Filter):
    """
    Suppress Log Records from registered logger

    Taken from ``aws_lambda_powertools.logging.filters.SuppressFilter``
    """
    def __init__(self, logger):
        self.logger = logger

    def filter(self, record):
        logger = record.name
        return False if self.logger in logger else True


class LambdaLoggerAdapter(logging.LoggerAdapter):
    """
    Lambda logger adapter.
    """
    def __init__(self, name, level=None, format_string=None):
        # Get logger, formatter
        logger = logging.getLogger(name)

        # Set log level
        logger.setLevel(level or LOG_LEVEL)

        # Set handler if necessary
        if not logger.handlers:  # and not logger.parent.handlers:
            formatter = logging.Formatter(format_string or LOG_FORMAT)
            handler = logging.StreamHandler()
            handler.setFormatter(formatter)
            logger.addHandler(handler)

        # Suppress AWS logging for this logger
        for handler in logging.root.handlers:
            logFilter = SuppressFilter(name)
            handler.addFilter(logFilter)

        # Initialize adapter with null RequestId
        super().__init__(logger, dict(reqid='-'))

    def attach(self, handler):
        """
        Decorate Lambda handler to attach logger to AWS request.

        :Example:

        >>> logger = lambo.getLogger(__name__)
        >>>
        >>> @logger.attach
        ... def handler(event, context):
        ...     logger.info('Hello, world!')
        ...     return {'ok': True}
        ...
        >>> handler({'fizz': 'buzz'})
        >>> # => INFO RequestId: {awsRequestId} EVENT {"fizz": "buzz"}
        >>> # => INFO RequestId: {awsRequestId} Hello, world!
        >>> # => INFO RequestId: {awsRequestId} RETURN {"ok": True}
        """
        def wrapper(event=None, context=None):
            try:
                self.addContext(context)
                self.info('EVENT %s', json.dumps(event, default=str))
                result = handler(event, context)
                self.info('RETURN %s', json.dumps(result, default=str))
                return result
            finally:
                self.dropContext()
        return wrapper

    def addContext(self, context=None):
        """
        Add runtime context to logger.
        """
        try:
            reqid = f'RequestId: {context.aws_request_id}'
        except AttributeError:
            reqid = '-'
        self.extra.update(reqid=reqid)
        return self

    def dropContext(self):
        """
        Drop runtime context from logger.
        """
        self.extra.update(reqid='-')
        return self


logger = LambdaLoggerAdapter('PyPI')


# LAMBDA HANDLERS

@logger.attach
def proxy_request(event, context=None):
    """
    Handle API Gateway proxy request.
    """
    # Get HTTP request method, path, and body
    method, package, body = parse_payload(event)

    # Get HTTP response
    try:
        res = ROUTES[method](package, body)
    except KeyError:
        res = reject(403, message='Forbidden')

    # Return proxy response
    logger.info('RESPONSE [%s]', res['statusCode'])
    return res


@logger.attach
def reindex_bucket(event=None, context=None):
    """
    Reindex S3 bucket.
    """
    # Get package names from common prefixes
    pages = S3_PAGINATOR.paginate(Bucket=S3_BUCKET, Delimiter='/')
    pkgs = (
        x.get('Prefix').strip('/')
        for page in pages
        for x in page.get('CommonPrefixes', [])
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


# LAMBDA HELPERS

def get_index():
    """
    GET /

    :return dict: Response
    """
    index = S3.get_object(Bucket=S3_BUCKET, Key='index.html')
    body = index['Body'].read().decode()
    return proxy_reponse(body)


def get_package_index(name):
    """
    GET /<pkg>

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
        return reject(404, message='Not Found')

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


def get_response(package, *_):
    """
    GET /*

    :param str path: Request path
    :return dict: Response
    """
    # GET /
    if package is None:
        return get_index()

    # GET /*
    return get_package_index(package)


def head_response(package, *_):
    """
    HEAD /*

    :param str path: Request path
    :return dict: Response
    """
    res = get_response(package)
    res.update(body='')
    return res


def parse_payload(event):
    """
    Get HTTP request method/path/body for v2 payloads.
    """
    routeKey = event.get('routeKey')
    pathParameters = event.get('pathParameters') or {}
    package = pathParameters.get('package')
    method, _ = routeKey.split(' ')
    body = event.get('body')
    logger.info(routeKey)
    return (method, package, body)


def post_response(package, body):
    """
    POST /

    :param str path: POST path
    :param str body: POST body
    :return dict: Response
    """
    if package is None:
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
            'content-length': len(body),
            'content-type': f'{content_type}; charset=utf-8',
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
        'content-length': len(body),
        'content-type': 'application/json; charset=utf-8',
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


class MiniTemplate(Template):
    def __init__(self, template):
        super().__init__(re.sub(r'\n *', '', template))


ROUTES = dict(GET=get_response, HEAD=head_response, POST=post_response)
ANCHOR = MiniTemplate('<a href="$href">$name</a><br>')
INDEX = MiniTemplate(
    '''
    <!DOCTYPE html>
    <html>
        <head>
            <meta name="pypi:repository-version" content="1.0">
            <title>$title</title>
        </head>
        <body>
            <h1>$title</h1>
            $anchors
        </body>
    </html>
    '''
)
SEARCH = MiniTemplate(
    '''
    <?xml version='1.0'?>
    <methodResponse>
        <params>
            <param>
                <value>
                    <array>
                        <data>$data</data>
                    </array>
                </value>
            </param>
        </params>
    </methodResponse>
    '''
)
SEARCH_VALUE = MiniTemplate(
    '''
    <struct>
        <member>
            <name>name</name>
            <value>
                <string>$name</string>
            </value>
        </member>
        <member>
            <name>summary</name>
            <value>
                <string>$summary</string>
            </value>
        </member>
        <member>
            <name>version</name>
            <value>
                <string>$version</string>
            </value>
        </member>
        <member>
            <name>_pypi_ordering</name>
            <value>
                <boolean>0</boolean>
            </value>
        </member>
    </struct>
    '''
)
