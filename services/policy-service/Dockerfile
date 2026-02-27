FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ ./app/

# Expose policy service port
EXPOSE 9000

# Run the policy service
CMD ["python", "-m", "app.main"]
