# Security Policy

## Supported Versions

We release patches for security vulnerabilities regularly. The following versions are currently supported:

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |
| < latest| :x:                |

We recommend always running the latest version to ensure you have all security patches.

## Reporting a Vulnerability

We take the security of **almudeer** seriously. If you believe you have found a security vulnerability, please report it to us as described below.

### How to Report

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via:

1. **GitHub Private Vulnerability Reporting** (preferred):
   - Go to the [Security tab](https://github.com/ayham-alali/almudeer/security)
   - Click "Report a vulnerability"
   - Provide details about the vulnerability


### What to Include

Please include the following information in your report:

- A description of the vulnerability
- Steps to reproduce the issue
- Affected versions
- Any potential impact
- If possible, suggestions for addressing the issue

### Response Timeline

- **Acknowledgment**: We will acknowledge receipt of your report within **48 hours**
- **Initial Assessment**: We will provide an initial assessment within **5 business days**
- **Resolution**: We aim to resolve critical vulnerabilities within **30 days**

### What to Expect

- You will receive a confirmation that your report has been received
- We may request additional information to understand the issue better
- You will be kept informed of our progress
- Once resolved, we may credit you for the discovery (with your permission)

## Security Best Practices

If you're using almudeer, we recommend:

1. **Keep dependencies updated** - Regularly update all dependencies to their latest secure versions
2. **Use environment variables** - Never commit sensitive data (API keys, passwords, etc.) to the repository
3. **Enable authentication** - Always use authentication in production environments
4. **Review logs regularly** - Monitor application logs for suspicious activity
5. **Use HTTPS** - Always use HTTPS in production environments

## Known Security Considerations

- Ensure `.env` files are never committed to version control
- Database credentials should be managed through environment variables or secrets management
- API keys and tokens should be rotated regularly

## Contact

For any questions about this security policy, please open an issue on the repository.

---

*Thank you for helping keep almudeer and its users safe!*
