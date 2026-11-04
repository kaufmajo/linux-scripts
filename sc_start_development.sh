#!/bin/bash

if [ "$(id -u)" -ne 0 ]
  then echo Please run this script as root or using sudo!
  exit
fi

# start apache
# grep -q prints nothing and only sets the exit status: 0 (true) if a line matches
if /etc/init.d/apache2 status | grep -q 'active (running) since'
then

    echo "Apache is currently running."

    service apache2 stop
    service apache2 start

else

    echo "Apache is not running."

    service apache2 start
fi


# start mariadb
if [ -f /etc/init.d/mariadb ]
then
    
    if /etc/init.d/mariadb status | grep -q 'mariadb is running'
    then

        echo "MariaDb is currently running."

        service mariadb stop
        service mariadb start

    else

        echo "MariaDb is not running."

        service mariadb start
    fi

fi
