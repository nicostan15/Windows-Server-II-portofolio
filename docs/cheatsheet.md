#login admins
vagrant ssh-config client
server3:
ssh -p 2207 -l 'WS26-JD\Administrator' -o PreferredAuthentications=password -o PasswordAuthentication=yes -o PubkeyAuthentication=no 127.0.0.1

