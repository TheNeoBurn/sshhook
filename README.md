# sshhook

Configure linux machine to register a port on a remote server to be accessable via SSH

- [Scenario](#Scenario)
- [Prepare the remote server](#PrepareRS)
  - [SSH machine: Create certificate](#SSHCreateCert)
  - [Remote server: Create user](#RSCreateUser)
  - [Remote server: Create command jail script](#RSCreateJail)
  - [Remote server: Configure SSH access for user](#RSConfigSSH)
- [Configure the SSH machine](#ConfigSSH)
  - [SSH machine: Create main task script](#SSHCreateMain)
  - [SSH machine: Register as daemon](#SSHRegisterDaemon)
  - [SSH machine: Create and configure a remote user](#SSHRemoteUser)
- [Connect for the client](#Connect)
  - [Client: Establish SSH connection through hop](#ClientConnect)

## <a name='Scenario'></a>Scenario

I have a linux machine I need to administer remotely but it is behind a non-accessable-to-me firewall and even then only accessable via IPv6.

So, what I wanna do is:
- Let the machine connect to a remote server via SSH
- Forward a remote port to the machine's SSH port
- Open the remote port to the public
- Access the machine through the forwarded port on the server

To make descriptions easier, I'll use these names:
- `SSH machine`: The linux machine I want to administer
- `remote server`: The server used as the port hop
- `clinet`: The machine I want to administer the SSH machine from


## <a name='PrepareRS'></a>Prepare the remote server

As I want the automate the port forwarding, the SSH machine needs a user on the remote machine an a way to access it via a certificate.

You'll need root rights to do all this, so be carefull! You can use `su` or `sudo -s` to change to root or prefix any commands with `sudo ...`.

### <a name='SSHCreateCert'></a>SSH machine: Create certificate

Hop onto your **SSH machine** and create a certificate as the user `root` with

```sh
ssh-keygen
```

Choose a fitting filename (e.g. `/root/.ssh/sshhook`) and **do not set a passphrase**, then copy the also created public key entry (e.g. `/root/.ssh/sshhook.pub`) which should look something like this:

```
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQ...P6U58= root@sshmachine
```

### <a name='RSCreateUser'></a>Remote server: Create user

Then, connect to your **remote server** and create a user for the incomming ssh to forward the port (e.g. `sshhook`) as root:

```sh
adduser sshhook
```

Set a **strong** random password - you won't need to type it in the future, although it might be required to log in at least once.

### <a name='RSCreateJail'></a>Remote server: Create command jail script

To add extra security we will create a simple script which is executed the client connects to prohibit any other commands or a shell to be used. The script can be anything but **it must not exit on its own***! I created the script `/home/sshhook/okay.sh`:

```sh
#! /bin/sh
echo Okay
while true
do
  sleep 1
done
```

Then make the file executable and owned by the user sshhook:

```sh
chmod +x /home/sshhook/okay.sh
chown sshhook:sshhook /home/sshhook/okay.sh
```

### <a name='RSConfigSSH'></a>Remote server: Configure SSH access for user

Edit the file `/home/sshhook/.ssh/authorized_keys` (you might need to create the directory and/or the file) and make sure it has the correct ownership and access rights:

```sh
mkdir /home/sshhook/.ssh
nano /home/sshhook/.ssh/authorized_keys
chown sshhook:sshhook /home/sshhook/.ssh/authorized_keys
chmod 644 /home/sshhook/.ssh/authorized_keys
```

In nano paste in your copied public key from the SSH machine and edit the line to start with your script as command to override anything a connecting client otherwise wants:

```
command="/home/sshhook/okay.sh" ssh-rsa AAAAB...
```

Edit your remote server's sshd config `/etc/ssh/sshd_config` to allow port gatewaws for the sshhook user by adding the following at the bottom:

```
Match User sshporter
  GatewayPorts yes
  AllowTcpForwarding yes
```

and restart your remote server's sshd daemon:

```
systemctl restart sshd
```

**You might also need to open the port in your firewall (e.g. iptables or ufw).**




## <a name='ConfigSSH'></a>Configure the SSH machine

### <a name='SSHCreateMain'></a>SSH machine: Create main task script

Connect to your SSH machine and create the main task script `/opt/sshhook.sh`:

```sh
nano /opt/sshhook.sh
```

Paste in the script:

```sh
#! /bin/sh
while true
do
  # Connect to remote server forwarding the port
  ssh -i /root/.ssh/sshhook -g -R \*:222:localhost:22 sshhook@remote.server
  # Give some pause bewteen attempts
  sleep 5
done
```

Some explaination:
- `-i file`: instructs ssh to use this identity file to authenticate
- `-g`: Makes the port forwarding a gateway port
- `-R remote_client:remote_port:localhost:local_port`: Requests a port forwarding from the remote port 222 to the local port 22, the remote_client makes sure **any** client can connect
- `sshhook@remote.server`: The user and remote server address (or IP)
- `-p port`: You can add this, if your remote server offers SSH connections on a different port

Make the script executable:

```sh
chmod +x /opt/sshhook.sh
```

At this time you should test your connection - especially becase it will ask you if the remote server's public key is correct and store it in known_hosts on the first connection.

```sh
/opt/sshhook.sh
```

You can close everything by quickly pressing [Ctrl]+[C] repeatedly as it will automatically reconnect otherwise.


### <a name='SSHRegisterDaemon'></a>SSH machine: Register as daemon

To make the process automatic I register a systemd daemon. Create the file `/etc/systemd/system/sshhook.service`:

```sh
nano /etc/systemd/system/sshhook.service
```

then paste the service description:

```ini
[Unit]
Description=SSH Hook
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/sshhook.sh
Restart=on-failure

[Install]
WantedBy=default.target
```

Enable and start the daemon and check its status:

```sh
systemctl enable sshhook
systemctl start sshhook
systemctl status sshhook
```

The status should look something like this:

```
● sshhook.service - SSH Hook
     Loaded: loaded (/etc/systemd/system/sshhook.service; enabled; preset: enabled)
     Active: active (running) since Sat 2023-06-31 09:50:31 BST; 3h 32min ago
   Main PID: 470 (sshhook.sh)
      Tasks: 2 (limit: 8990)
     Memory: 6.1M
        CPU: 45min 6.377s
     CGroup: /system.slice/sshhook.service
             ├─470 /bin/sh /opt/sshhook.sh
             └─525 ssh -i /root/.ssh/sshhook -g -R "*:222:localhost:22" sshhook@remote.server

Jun 31 09:50:41 bjsbck systemd[1]: Started sshhook.service - SSH Hook.
Jun 31 09:50:41 bjsbck sshhook.sh[525]: Pseudo-terminal will not be allocated because stdin is not a terminal.
Jun 31 09:50:43 bjsbck sshhook.sh[525]: Okay
```

### <a name='SSHRemoteUser'></a>SSH machine: Create and configure a remote user

As you set everything up I'm sure you already have an SSH user on the machine so let's just say:
- You'll need sshd running (with this example on the default port 22)
- You'll need a user allowed to access the SSH machine via SSH

## <a name='Connect'></a>Connect for the client

### <a name='ClientConnect'></a>Client: Establish SSH connection through hop

Connecting to your SSH machine through the remote server is strait forward now:

```sh
ssh -p 222 sshuser@remote.server
```

et voilà: it should connect you right throug to your SSH machine.
