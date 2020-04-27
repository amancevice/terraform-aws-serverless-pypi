#!/usr/bin/env python3
# usage:
#   python server.py --help
import argparse
import logging
import socketserver
from http import server

import index

logging.basicConfig(format='%(message)s')
logging.getLogger().setLevel(logging.INFO)


def get_opts():
    parser = argparse.ArgumentParser(description='Start a simple PyPI server')
    parser.add_argument(
        '-b', '--base-path',
        dest='base_path',
        default='simple',
        help='Base path.',
        metavar='STR',
        type=str,
    )
    parser.add_argument(
        '-p', '--port',
        dest='port',
        default='8000',
        help='Port number.',
        metavar='INT',
        type=int,
    )
    return parser.parse_args()


class PyPI(server.SimpleHTTPRequestHandler):
    def log_headers(self):
        for key, val in self.headers.items():
            msg = f'HEADER -- {key}: {val}'
            msg = f'{msg[:76]}...' if len(msg) > 79 else msg
            logging.info(msg)

    def get_response(self, httpMethod):
        # Log request headers
        self.log_headers()
        logging.info(f'PATH -- {self.path}')

        # Construct event
        event = {
            'httpMethod': httpMethod,
            'path': self.path,
        }

        # Get response
        response = index.proxy_request(event)
        status = response.get('statusCode')
        headers = response.get('headers')
        self.send_response(status)
        for key, val in headers.items():
            self.send_header(key, val)
        self.end_headers()

    def do_GET(self):
        self.get_response('GET')

    def do_HEAD(self):
        self.get_response('HEAD')


if __name__ == '__main__':
    opts = get_opts()
    index.BASE_PATH = opts.base_path
    with socketserver.TCPServer(('', opts.port), PyPI) as httpd:
        logging.info(
            f'Starting PyPI at http://localhost:{opts.port}/{opts.base_path}/')
        httpd.serve_forever()
