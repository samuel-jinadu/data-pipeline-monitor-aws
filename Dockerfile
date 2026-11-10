# Use a lightweight Python image
FROM python:3.12-slim

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Set working directory
WORKDIR /app

# Copy dependency files first (for Docker layer caching)
COPY streamlit-app/pyproject.toml streamlit-app/uv.lock ./

# Install dependencies into the system python
RUN uv pip install --system -r pyproject.toml

# Copy the rest of the application code
COPY streamlit-app/app.py ./

# Streamlit runs on port 8501 by default
EXPOSE 8501

# Command to run the application
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0"]