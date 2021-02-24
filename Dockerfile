ARG PYTHON_VERSION=3.8
FROM amazon/aws-lambda-python:${PYTHON_VERSION}
RUN pip install pipenv==2020.11.15
RUN pipenv install 2>&1
COPY . .
RUN pipenv lock -r > requirements.txt
RUN pipenv lock -r -d > requirements-dev.txt
RUN pip install -r requirements-dev.txt
ENV PYTHONPATH=/opt/python:/var/task
EXPOSE 8080
VOLUME /opt/python
VOLUME /root
VOLUME /var/task
