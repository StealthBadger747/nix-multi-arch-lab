# YourCarOfTheDay Email Queue Worker

A Python-based email queue worker for the YourCarOfTheDay service. This service processes email jobs from a Redis queue and sends emails to users.

## Features

- Processes daily car emails
- Sends comment reply notifications
- Uses BullMQ for Redis-based job queue
- Built with Nix for reproducible development and deployment

## Requirements

- [Nix](https://nixos.org/download.html) with flakes enabled
- Redis server (configured via environment variables)
- SMTP server (configured via environment variables)

## Environment Variables

This service requires the following environment variables:

```
REDIS_URL=redis://localhost:6379
SMTP_HOST=smtp.example.com
SMTP_PORT=465
SMTP_USER=user@example.com
SMTP_PASS=password
```

## Development

To set up a development environment:

```bash
# Enter development shell with all dependencies
nix develop

# Run the service
python main.py
```

## Deployment

To build a deployable package:

```bash
# Build the package
nix build

# Run the service from the package
./result/bin/ycotd-email-queue
```

## Architecture

The service connects to a Redis instance and processes jobs from the `ycotdEmailQueue` queue. Each job contains email data including:

- Email type (`dailyCarEmail` or `commentReply`)
- Recipient email address
- Context data for the email template

The service processes each job by:
1. Constructing the appropriate email using HTML templates
2. Sending the email via SMTP
3. Adding a delay for rate limiting

## License

Proprietary - YourCarOfTheDay
