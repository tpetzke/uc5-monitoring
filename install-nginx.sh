#! /bin/bash
sudo apt-get update
sudo apt-get upgrade -y
sudo apt install nginx -y
echo "<body bgcolor=\"#000000\" style=\"color:#5800FF;\"><br><br><br><H1 align=\"middle\">Kyndryl Use Case 5 Demonstration</H1>" | sudo tee /var/www/html/index.html
echo "<H4 align=\"middle\">Diese Seite wurde ihnen praesentiert von WebServer</H4><H1 align=\"middle\">" | sudo tee -a /var/www/html/index.html
echo $HOSTNAME | sudo tee -a /var/www/html/index.html
echo "</H1></body>" | sudo tee -a /var/www/html/index.html

# download package
# Escape the $ sign with $$ as Terraform will complain otherwise
curl -s https://repos.influxdata.com/influxdb.key | sudo apt-key add -
source /etc/lsb-release
echo "deb https://repos.influxdata.com/$${DISTRIB_ID,,} $${DISTRIB_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/influxdb.list

# install the telegraf agent
sudo apt-get update
sudo apt-get install telegraf -y

# Write a new telegraf config with Azure Monitor added 
# Disable TLS as it has no key and will run in an error
telegraf --input-filter cpu:mem:nginx --output-filter azure_monitor config | sudo tee /etc/telegraf/telegraf.conf
sudo sed 's/tls_/#tls_/' /etc/telegraf/telegraf.conf -i

# add the nginx status display location to the config
# start with line 47, bit dirty but works
sudo sed -i '47 a location /server_status {' /etc/nginx/sites-enabled/default
sudo sed -i '48 a stub_status on;' /etc/nginx/sites-enabled/default
sudo sed -i '49 a access_log off;' /etc/nginx/sites-enabled/default
sudo sed -i '50 a allow all;' /etc/nginx/sites-enabled/default
sudo sed -i '51 a }' /etc/nginx/sites-enabled/default

# restart nginx & telegraf
sudo systemctl restart nginx
sudo systemctl restart telegraf
