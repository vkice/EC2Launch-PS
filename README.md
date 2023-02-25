# EC2Launch-PS
Simple Powershell script for quickly spinning up EC2 Instances on AWS for testing purposes. Created for personal use.

  - AWS CLI must be installed and profile/credentials configured.

  - Generates SSH Keys to use for launched Instance.
  - Designed to quickly spin up a test instance from a Windows workstation.
  - Option to terminate instance and SSH keys.
  - Allows use of custom user-data script.
  - Instance ID, Public DNS name, JSON formatted Instance details, and SSH key added to a new folder.

# Versions

  - Quick-EC2-Launch-Connect: Launched a single t2.micro instance with a new SSH key, creates a new PS window allowing SSH access with original PS window allowing cleanup option to delete Instance and SSH key pair, with default VPC/Subet/SG settings.
  - Putty-EC2-Launch: Similar to above but generates a PPK key instead, for use with Putty.
  - AIO-EC2-Launch: More interactive and customized option which allows the following choices
    - Instance type
    - Number of instances
    - PEM or PPK key
    - Subnet
    - Security Group rules for current local public IP address
    - User-data

# Issues

  - Finding copy to clipboard does not work too well, output is provided for a quick Ctrl+Shift+V copy.
  - Cleanup is limited to keeping PS window open, otherwise resources should be deleted to prevent unnecessary costs.
