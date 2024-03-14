# Atualmente, o script irá baixar e configurar os servidores de retransmissão e sinal (hbbr e hbbs),
# gerar configurações e hospedá-las em uma página da web protegida por senha para implantação simples nos clientes.

# Requisitos
 Você precisa ter o Linux instalado, o script é testado funcionando com CentOS Linux 7/8, Ubuntu 18/20 e Debian.
 Um servidor com 1 CPU, 1 GB de RAM e 10 GB de disco é suficiente para rodar o RustDesk.

# Como instalar o servidor
 Configure seu firewall em seu servidor antes de executar o script.

# Certifique-se de ter acesso via SSH ou de outra forma configurada antes de configurar o firewall. 
 Os comandos de exemplo para UFW (baseado em Debian) são:

# Libere as portas:
ufw allow 21115:21119/tcp
ufw allow 8000/tcp
ufw allow 21116/udp
sudo ufw enable

# Execute o script de instalação:
<code>
wget https://raw.githubusercontent.com/techahold/rustdeskinstall/master/install.sh
chmod +x install.sh
./install.sh
</code>

