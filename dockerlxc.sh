#!/bin/bash

# Function to display a menu for user to select the option
select_option() {
  echo "Please select an option:"
  PS3="Your choice: "
  select option in "$@"; do
    if [[ -n "$option" ]]; then
      echo "You selected: $option"
      break
    else
      echo "Invalid selection. Please try again."
    fi
  done
}

# Function to install Docker
install_docker() {
    echo "Would you like to install Docker?"
    select_option "Yes" "No"
    if [[ "$option" == "Yes" ]]; then
        echo "Installing Docker..."

        # Install Docker
        lxc-attach -n "$container_name" -- apt-get update
        lxc-attach -n "$container_name" -- apt-get install -y \
            ca-certificates curl gnupg lsb-release

        # Add Docker repository and install Docker
        lxc-attach -n "$container_name" -- curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
        lxc-attach -n "$container_name" -- echo "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        lxc-attach -n "$container_name" -- apt-get update
        lxc-attach -n "$container_name" -- apt-get install -y docker-ce docker-ce-cli containerd.io

        echo "Docker installation complete!"
    else
        echo "Skipping Docker installation."
    fi
}

# Function to install Docker Compose
install_docker_compose() {
    echo "Would you like to install Docker Compose?"
    select_option "Yes" "No"
    if [[ "$option" == "Yes" ]]; then
        echo "Installing Docker Compose..."

        # Install Docker Compose
        lxc-attach -n "$container_name" -- curl -L "https://github.com/docker/compose/releases/download/$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        lxc-attach -n "$container_name" -- chmod +x /usr/local/bin/docker-compose

        echo "Docker Compose installation complete!"
    else
        echo "Skipping Docker Compose installation."
    fi
}

# Function to install Portainer
install_portainer() {
    echo "Would you like to install Portainer?"
    select_option "Yes" "No"
    if [[ "$option" == "Yes" ]]; then
        echo "Installing Portainer..."

        # Install Portainer as Docker container
        lxc-attach -n "$container_name" -- docker volume create portainer_data
        lxc-attach -n "$container_name" -- docker run -d -p 9000:9000 --name portainer --restart always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce

        echo "Portainer installation complete!"
    else
        echo "Skipping Portainer installation."
    fi
}

# Function to configure CIFS share
configure_cifs_share() {
    echo "Would you like to create a CIFS share mount?"
    select_option "Yes" "No"
    if [[ "$option" == "Yes" ]]; then
        echo "Please enter the details for the CIFS share:"

        # Gather details for CIFS share
        read -p "Enter the IP address of the CIFS server (e.g., 10.1.1.5): " cifs_ip
        read -p "Enter the share name (e.g., software): " cifs_share
        read -p "Enter the local mount point (e.g., /mnt/synology/software): " local_mount
        read -p "Enter the username for the CIFS share: " cifs_username
        read -sp "Enter the password for the CIFS share: " cifs_password
        echo ""

        # Check if the local folder exists, create it if necessary
        if [[ ! -d "$local_mount" ]]; then
            echo "Local folder $local_mount does not exist. Creating it..."
            mkdir -p "$local_mount"
        fi

        # Add the CIFS share entry to /etc/fstab
        fstab_entry="//${cifs_ip}/${cifs_share} ${local_mount} cifs username=${cifs_username},password=${cifs_password},_netdev,uid=1000,gid=1000,vers=2.1 0 0"
        echo "$fstab_entry" >> /etc/fstab
        echo "CIFS share entry added to /etc/fstab."

        # Optionally mount the CIFS share immediately
        echo "Would you like to mount the CIFS share now?"
        select_option "Yes" "No"
        if [[ "$option" == "Yes" ]]; then
            mount "$local_mount"
            echo "CIFS share mounted successfully!"
        fi
    else
        echo "Skipping CIFS share creation."
    fi
}

# Ask for container name
read -p "Enter the name for the LXC container: " container_name

# Ask for privileged or unprivileged container
select_option "Privileged" "Unprivileged"
privileged_choice=$option

# Ask for CPU cores
read -p "Enter the number of CPU cores for the container: " cpu_cores

# Ask for RAM
read -p "Enter the amount of RAM (in MB) for the container: " ram

# Ask for IP address and netmask
read -p "Enter the IP address for the container (e.g., 192.168.1.100): " ip_address
read -p "Enter the netmask for the container (e.g., 255.255.255.0): " netmask

# Ask if SSH access is required
select_option "Yes" "No"
ssh_access_choice=$option

# Ask for username and password for the container
read -p "Enter the username for the LXC container: " lxc_username
read -sp "Enter the password for the LXC container: " lxc_password
echo ""

# Prepare the container configuration
lxc_config_file="/var/lib/lxc/$container_name/config"

# Create the LXC container based on Debian 12 (if not already created)
if ! lxc-ls --fancy | grep -q "$container_name"; then
    echo "Creating the container: $container_name..."
    if [[ "$privileged_choice" == "Privileged" ]]; then
        lxc-create -n "$container_name" -t debian -- -r bookworm
    else
        lxc-create -n "$container_name" -t debian -- -r bookworm -B lvm
    fi
else
    echo "Container $container_name already exists. Skipping creation."
fi

# Start the container
echo "Starting the container..."
lxc-start -n "$container_name"

# Configure the container
echo "Configuring the container..."

# Set CPU and RAM limits
echo "lxc.cgroup.cpu.shares = $cpu_cores" >> $lxc_config_file
echo "lxc.cgroup.memory.limit_in_bytes = ${ram}M" >> $lxc_config_file

# Network configuration (static IP)
echo "lxc.network.0.type = veth" >> $lxc_config_file
echo "lxc.network.0.link = lxcbr0" >> $lxc_config_file
echo "lxc.network.0.ipv4 = $ip_address" >> $lxc_config_file
echo "lxc.network.0.ipv4.gateway = 192.168.1.1" >> $lxc_config_file
echo "lxc.network.0.ipv4.netmask = $netmask" >> $lxc_config_file

# Configure SSH access if required
if [[ "$ssh_access_choice" == "Yes" ]]; then
    echo "Enabling SSH access..."
    echo "lxc.start.auto = 1" >> $lxc_config_file
    echo "lxc.ssh.authorized_keys = /root/.ssh/authorized_keys" >> $lxc_config_file
    mkdir -p /var/lib/lxc/$container_name/rootfs/root/.ssh
    touch /var/lib/lxc/$container_name/rootfs/root/.ssh/authorized_keys
fi

# Create user and set password inside the container
echo "Creating user and setting password inside the container..."
lxc-attach -n "$container_name" -- useradd -m -s /bin/bash "$lxc_username"
echo "$lxc_username:$lxc_password" | lxc-attach -n "$container_name" -- chpasswd

# Set root password
echo "Setting root password inside the container..."
echo "root:$lxc_password" | lxc-attach -n "$container_name" -- chpasswd

# Ask for Docker installation
install_docker

# Ask for Docker Compose installation
install_docker_compose

# Ask for Portainer installation
install_portainer

# Ask for CIFS Share
configure_cifs_share

# Print final info
echo "LXC Container $container_name has been created and configured successfully."
echo "To access the container, you can use:"
echo "    lxc-attach -n $container_name"
