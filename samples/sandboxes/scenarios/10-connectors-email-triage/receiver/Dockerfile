# Receiver container image for the sandboxes-connectors-email-triage
# scenario. Slim Python image; only deps are listed in requirements.txt.

FROM mcr.microsoft.com/azurelinux/base/python:3.12

WORKDIR /app

# Install dependencies first so re-builds with unchanged requirements
# can reuse the layer.
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Honour PORT if the platform sets one; ACA defaults targetPort=8080.
ENV PORT=8080
EXPOSE 8080

# Drop privileges. Container Apps doesn't require this, but it's good
# hygiene for any image that handles untrusted webhook payloads.
RUN groupadd --system app && useradd --system --gid app --no-create-home app
USER app

CMD ["sh", "-c", "uvicorn app:app --host 0.0.0.0 --port ${PORT}"]
