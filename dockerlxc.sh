#!/bin/bash

# Function to install necessary dependencies
install_dependencies() {
    apt update
    apt install -y lxc lxc-debian jq cifs-utils wget curl
}

# Function to pull the latest Debian LXC template
pull_debian_template() {
    echo "Fetching the latest Debian LXC template..."
    lxc-create -n dummy -t debian
    if [ $? -ne 0 ]; then
        echo "Error: Failed to pull the Debian LXC template."
        exit 1
    fi
    lxc-destroy -n dummy  # Clean up the dummy container
    echo "Debian LXC template fetched successfully!"
}

# Function to create the LXC container
create_lxc_container() {
    echo "Enter the name for the LXC container:"
    read container_name

    echo "Please select an option:
    1) Privileged
    2) Unprivileged"
    read -p "Your choice: " container_type
    if [[ "$container_type" == "1" ]]; then
        container_type="privileged"
    else
        container_type="unprivileged"
    fi
    echo "You selected: $container_type"

    echo "Enter the number of CPU cores for the container:"
    read cpu_cores
    echo "Enter the amount of RAM (in MB) for the container:"
    read ram
    echo "Enter the IP address for the container (e.g., 192.168.1.100):"
    read ip_address
    echo "Enter the netmask for the container (e.g., 255.255.255.0):"
    read netmask

    echo "Please select an option:
    1) Yes
    2) No"
    read -p "Would you like to enable SSH access? " ssh_enabled
    if [[ "$ssh_enabled" == "1" ]]; then
        ssh_enabled="true"
    else
        ssh_enabled="false"
    fi

    echo "Enter the username for the LXC container:"
    read lxc_user
    echo "Enter the password for the LXC container:"
    read -s lxc_password

    # Create the LXC container with specified settings
    echo "Creating the container: $container_name..."
    lxc-create -t debian -n $container_name -- -r bookworm
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create LXC container."
        exit 1
    fi

    # Configure container settings
    echo "Configuring the container..."
    lxc_cconfig_file="/var/lib/lxc/$container_name/config"
    
    # Update CPU and memory settings
    echo "lxc.cgroup2.memory.max = $ram" >> $lxc_cconfig_file
    echo "lxc.cgroup2.cpuset.cpus = 0-$((cpu_cores-1))" >> $lxc_cconfig_file
    echo "lxc.net.0.ipv4.address = $ip_address" >> $lxc_cconfig_file
    echo "lxc.net.0.ipv4.netmask = $netmask" >> $lxc_cconfig_file

    # Enable SSH if requested
    if [ "$ssh_enabled" == "true" ]; then
        echo "Enabling SSH access..."
        echo "lxc.mount.entry = /dev/net/tun dev/net/tun none bind,create=dir" >> $lxc_cconfig_file
        echo "lxc.start.order = 10" >> $lxc_cconfig_file
    fi

    # Set up user and password inside the container
    echo "Creating user and setting password inside the container..."
    lxc-start -n $container_name
    sleep 5  # Give the container a moment to start
    lxc-attach -n $container_name -- useradd -m $lxc_user
    echo "$lxc_user:$lxc_password" | lxc-attach -n $container_name -- chpasswd

    # Starting the container
    echo "Starting the container..."
    lxc-start -n $container_name
    if [ $? -ne 0 ]; then
        echo "Error: Failed to start the container."
        exit 1
    fi
    echo "LXC Container $container_name has been created and started."

    # Optionally install Docker
    echo "Would you like to install Docker?"
    read -p "Your choice (1 for Yes, 2 for No): " docker_install
    if [[ "$docker_install" == "1" ]]; then
        echo "Installing Docker..."
        lxc-attach -n $container_name -- bash -c "$(curl -fsSL https://get.docker.com -o get-docker.sh)"
        lxc-attach -n $container_name -- sh get-docker.sh
        echo "Docker installation complete!"
    fi

    # Optionally install Docker Compose
    echo "Would you like to install Docker Compose?"
    read -p "Your choice (1 for Yes, 2 for No): " compose_install
    if [[ "$compose_install" == "1" ]]; then
        echo "Installing Docker Compose..."
        lxc-attach -n $container_name -- curl -L https://github.com/docker/compose/releases/download/$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
        lxc-attach -n $container_name -- chmod +x /usr/local/bin/docker-compose
        echo "Docker Compose installation complete!"
    fi

    # Optionally install Portainer
    echo "Would you like to install Portainer?"
    read -p "Your choice (1 for Yes, 2 for No): " portainer_install
    if [[ "$portainer_install" == "1" ]]; then
        echo "Installing Portainer..."
        lxc-attach -n $container_name -- docker volume create portainer_data
        lxc-attach -n $container_name -- docker run -d -p 9000:9000 --name portainer --restart always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce
        echo "Portainer installation complete!"
    fi

    # Optionally set up CIFS share
    echo "Would you like to create a CIFS share mount?"
    read -p "Your choice (1 for Yes, 2 for No): " cifs_share
    if [[ "$cifs_share" == "1" ]]; then
        echo "Please enter the details for the CIFS share:"
        echo "Enter the IP address of the CIFS server (e.g., 10.1.1.5):"
        read cifs_ip
        echo "Enter the share name (e.g., software):"
        read cifs_share_name
        echo "Enter the local mount point (e.g., /mnt/synology/software):"
        read cifs_mount_point
        echo "Enter the username for the CIFS share:"
        read cifs_user
        echo "Enter the password for the CIFS share:"
        read -s cifs_password

        # Create local mount directory
        mkdir -p $cifs_mount_point

        # Add entry to /etc/fstab
        echo "//${cifs_ip}/${cifs_share_name} ${cifs_mount_point} cifs username=${cifs_user},password=${cifs_password},_netdev,uid=1000,gid=1000,vers=2.1 0 0" >> /etc/fstab
        systemctl daemon-reload
        mount -a

        echo "CIFS share entry added to /etc/fstab."
        echo "CIFS share mounted successfully!"
    fi

    echo "LXC Container $container_name has been created and configured successfully!"
    echo "To access the container, use the following command: lxc-attach -n $container_name"
}

# Main script execution
install_dependencies
pull_debian_template
create_lxc_container
