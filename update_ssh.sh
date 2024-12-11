#!/bin/bash

# Check if running with root privileges
if [ "$(id -u)" != "0" ]; then
   echo "Error: Root privileges required" 
   exit 1
fi

# Error handling
set -e

# Record current path
current_path=$(pwd)

# Install dependencies
prepare_environment() {
    yum clean all
#   yum makecache
    yum install -y gcc gcc-c++ make wget tar zlib-devel perl openssl-devel pam-devel krb5-devel
}

# Install zlib
install_zlib() {
    echo "Installing Zlib..."
    cd "$current_path"
    
    # Check if source file exists
    if [ ! -f "zlib-1.3.1.tar.gz" ]; then
        wget https://www.zlib.net/zlib-1.3.1.tar.gz
    fi
    
    tar -xzf zlib-1.3.1.tar.gz
    cd zlib-1.3.1
    ./configure --prefix=/usr/local/zlib
    make && make install
    
    # Update library path
    echo "/usr/local/zlib/lib" >> /etc/ld.so.conf.d/zlib.conf
    ldconfig
    
    echo "Zlib installation completed"
    
    # Verify zlib version
    zlib_version=$(zlib-config --version 2>/dev/null || echo "Version check failed")
    echo "Installed Zlib Version: $zlib_version"
    
    # Additional verification methods
    ls /usr/local/zlib/lib
    file /usr/local/zlib/lib/libz.so*
}

# Install OpenSSL
install_openssl() {
    echo "Installing OpenSSL..."
    cd "$current_path"
    
    # Check if source file exists
    if [ ! -f "openssl-3.4.0.tar.gz" ]; then
        wget https://github.com/openssl/openssl/releases/download/openssl-3.4.0/openssl-3.4.0.tar.gz
    fi
    
    tar -xzf openssl-3.4.0.tar.gz
    cd openssl-3.4.0
    
    # Configuration and compilation
    ./config --prefix=/usr/local/openssl --openssldir=/etc/ssl shared zlib -fPIC
    make -j$(nproc) && make install
    
    # Backup and replace original openssl
    backup_date=$(date +"%Y%m%d")
    mv /usr/bin/openssl "/usr/bin/openssl_${backup_date}.bak"
    
    # Create symbolic links
    ln -sf /usr/local/openssl/bin/openssl /usr/bin/openssl
    
    # Update library path
    echo "/usr/local/openssl/lib64" >> /etc/ld.so.conf.d/openssl.conf
    ldconfig
    
    # Verify OpenSSL version
    openssl version
    
    echo "OpenSSL installation completed"
}

# Install OpenSSH
install_openssh() {
    echo "Installing OpenSSH..."
    
    # Backup original configuration
    backup_date=$(date +"%Y%m%d")
    mkdir -p ~/ssh_openssh_"${backup_date}"_bak
    cp /etc/ssh/sshd_config ~/ssh_openssh_"${backup_date}"_bak/
    cp /etc/pam.d/sshd ~/ssh_openssh_"${backup_date}"_bak/
    
    # Remove existing openssh
    yum remove -y openssh*
    
    # Install compilation dependencies
    yum install -y pam-devel

    # Compile and install
    cd "$current_path"
    
    # Check if source file exists
    if [ ! -f "openssh-9.9p1.tar.gz" ]; then
        wget https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-9.9p1.tar.gz
    fi
    
    tar -xzf openssh-9.9p1.tar.gz
    cd openssh-9.9p1
    
    ./configure \
        --prefix=/usr/local/openssh \
        --sysconfdir=/etc/ssh \
        --with-ssl-dir=/usr/local/openssl \
        --with-zlib=/usr/local/zlib \
        --with-pam
    
    make -j$(nproc) && make install
    
    # Set key file permissions
    chmod 0600 /etc/ssh/ssh_host_*_key
    
    # Copy service scripts and configurations
    cp contrib/redhat/sshd.init /etc/init.d/sshd
    cp contrib/redhat/sshd.pam /etc/pam.d/sshd
    
    # Copy executable files
    cp /usr/local/openssh/sbin/sshd /usr/sbin/sshd
    cp /usr/local/openssh/bin/* /usr/bin/
    
    # Add ssh-copy-id
    cp contrib/ssh-copy-id /usr/bin/
    chmod 0755 /usr/bin/ssh-copy-id
    
    # Configure sshd service
    chmod u+x /etc/init.d/sshd
    chkconfig --add sshd
    chkconfig sshd on
    
    # Modify sshd configuration
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^Subsystem.*sftp.*/Subsystem sftp \/usr\/local\/openssh\/libexec\/sftp-server/' /etc/ssh/sshd_config
    
    # Restart service and verify
    systemctl restart sshd
    systemctl status sshd
    ssh -V
    
    echo "OpenSSH installation completed"
}

# Main function
main() {
    prepare_environment
    install_openssl
    install_openssh
    
    echo "SSH and SSL upgrade successful"
}

# Execute main function
main

