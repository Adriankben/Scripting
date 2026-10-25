# Update and Upgrade System
sudo apt update && sudo apt upgrade -y && sudo apt full-upgrade -y && sudo apt autoremove -y

# Configure UFW (Uncomplicated Firewall)
sudo apt install ufw -y
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable

# Allow necessary protocols/ports
sudo ufw allow ssh          # Default SSH port 22 (change if needed)
# Example for custom SSH port:
# sudo ufw allow 2222/tcp   

# Install and Configure Fail2Ban
sudo apt install fail2ban -y

# Preserve custom Fail2Ban config by copying jail.conf to jail.local
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# (Optional) Edit jail.local to enable/adjust jails as needed

# Install Lynis Security Auditing Tool
sudo apt install lynis -y
sudo lynis audit system

# Helpful tools to monitor bugs and restarts
# apt-listbugs: lists critical bugs before APT install/upgrade
# needrestart: alerts for services needing restart after updates

# Install and run rkhunter for rootkit detection
sudo apt install rkhunter -y
sudo rkhunter --update
sudo rkhunter --check

# -----------------------------------------
# SSH Hardening

# Backup current SSH config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Edit SSH config
sudo nano /etc/ssh/sshd_config

# Recommended changes to add or modify:
# PermitRootLogin no
# PasswordAuthentication no
# Port 2222               # Example custom SSH port, change as needed
# AllowUsers yourusername # Replace with your actual username

# Allow custom SSH port through firewall (if changed)
sudo ufw allow 2222/tcp    # Replace 2222 with your chosen port

# Restart SSH service to apply changes
sudo systemctl restart ssh

# -----------------------------------------
# SSH Key-Based Authentication Setup (if not already done)

# On Kali (SSH server):
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# On Client machine:
ssh-keygen                   # Generate SSH key pair if needed

# Copy public key to Kali server (replace IP/hostname and port):
ssh-copy-id -p 2222 yourusername@kali-ip

# -----------------------------------------
# To restore original SSH config (if needed):
sudo cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
sudo systemctl restart ssh

# -----------------------------------------
# End of script
