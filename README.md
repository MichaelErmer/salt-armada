salt-armada
===========

This repository contains the salt states that installs stationspinner and
armada, according to your configuration. Below is instructions on how to get it
up and running for testing purposes. The same recipe works for production use,
but armada is not in a state where you should be doing that regardless.


//vitt

Prerequisites
=============

Creating the VM
---------------

For this test setup, you'll need ubuntu server 14.04 lts, download it here:
http://releases.ubuntu.com/14.04.1/ubuntu-14.04.1-server-amd64.iso

I'm using virtualbox on windows for creating the VM, but anything will work. My
target platform is ubuntu 14.04 lts with 1 core, 1 gb ram, 30gb disk, a
standard digitalocean.com vps.

Install ubuntu as normal. I usually use UTC as timezone, instead of my local
tz, but stationspinner should work regardless. Don't select any services except
OpenSSH during setup.

Setting up salt
---------------

After the installation has finished, reboot, log in and sudo to root:

    sudo -s
  
Update the server and reboot:

    apt-get update
    apt-get dist-upgrade
    reboot
  
Add the saltstack ppa and install:

    add-apt-repository ppa:saltstack/salt
    apt-get update
    apt-get install salt-minion git
  
If set up correctly, you should now have salt-minion 2014.7 or newer installed:

    root@armada:~# salt-minion --versions
              Salt: 2014.7.0
            Python: 2.7.6 (default, Mar 22 2014, 22:59:56)
            Jinja2: 2.7.2
          M2Crypto: 0.21.1
    msgpack-python: 0.3.0
      msgpack-pure: Not Installed
          pycrypto: 2.6.1
           libnacl: Not Installed
            PyYAML: 3.10
             ioflo: Not Installed
             PyZMQ: 14.0.1
              RAET: Not Installed
               ZMQ: 4.0.4
              Mako: 0.9.1


Configuring salt to use salt-armada
-----------------------------------

We will run salt in a masterless setup for this.
Open /etc/salt/minion and uncomment this line:

    #default_include: minion.d/*.conf

It will make salt read all the .conf files in /etc/salt/minion.d
Put the following contents into /etc/salt/minion.d/roots.conf:

    file_client: local
    file_roots:
      base:
        - /srv/salt
    
    pillar_roots:
      base:
        - /srv/pillar

Checkout the salt-armada git repository:

    cd /srv
    git clone https://github.com/kriberg/salt-armada.git salt

Unfourtunately, salt doesn't support git remotes in masterless setups yet. You
will have to do git pull in /srv/salt manually, to get updates to the scripts,
if needed.

Next, create the pillar directory and restart salt:

    mkdir -p /srv/pillar/armada
    service salt-minion restart

Configuring armada and stationspinner
=====================================

The salt-armada scripts configures the system according to the parameters you
put in the salt pillar, which is just yaml files with hierarchical data. Check
this link for examples of the data:
https://github.com/kriberg/salt-armada/blob/master/pillar.example

The filenames are commented out at the top. Copy/paste the data into them, but
make sure you keep the indentation. In armada.sls, set your server_name to
either your IP address or a resolvable hostname. It will be used as the
server_name parameter to nginx.

In stationspinner.sls, for allowed_hosts, add the same value as you used for
server_name:

    allowed_hosts:
      - localhost
      - myhostname.com
    
This will be read by django's settings. Also change admins and add your email,
username and full_name. This isn't for your OS user, but for the user you will
be using for administration.

You can change 'markets' too, if you don't need all those indexed and want to
save cpu and/or diskspace.

The list for 'evemail_search_languages' indicates which languages will be used
to create the search index. If all the mail is predominately in english, that
will suffice. If you're in a mixed alliance or run for multiple entities with
several languages, you can make the mail search better by adding additional
indexing languages here. To stick with english only, use:

    evemail_search_languages:
      - english

PostgreSQL currently supports the following languages:

* danish
* dutch
* english
* finnish
* french
* german
* hungarian
* italian
* norwegian
* portuguese
* romanian
* russian
* spanish
* swedish
* turkish

To add a some, simply append them to the configuration. The bieffect of adding more
languages is a slight increase in the time it takes to parse mails, usually around
10-30 ms, and increased database size.

Now we have configured armada, stationspinner and our databases. Put this into
/srv/pillar/top.sls:

    base:
      '*':
        - armada.stationspinner
        - armada.databases
        - armada.armada

This will make the config visible to salt to the server. To make sure you can
see all parameters correctly, run:

    salt-call pillar.item armada stationspinner postgres
  
You should get a nice printout in blue, green and yellow. Look for any errors
and try to correct them if you can see something like "<=======" somewhere.
YAML used two spaces as indentation. If everything looks fine, you're ready to
install.

Before installing stationspinner, you need to configure an email service.
By default, stationspinner tries to connect to SMTP running on localhost at
port 25. There's several ways to setup email, but a basic setup for a server
with a FQDN can be done with:

    apt-get install postfix

Then select "Internet Site". You can also use "Local only", if you only intend
to test it personally. Configuring email is way beyond the scope of these
instrutions though, so gl hf.

Installing stationspinner
=========================

Now as everything is configured, we can install or update both stationspinner
and armada using salt. Stationspinner is split into three parts:

    * database - The postgresql and redis databases.
    * api - The REST endpoints that armada will connect to.
    * worker - The eveapi processing workers.

You only need a single instance of these, but if you are processing a large
amount of eve API keys, it will help to have multiple workers. Be aware though,
the workers require access to the Redis instance running on the server
allocated as database. Albeit there's a password protecting the Redis database,
there's no strong authentication and authorization built into Redis. Only use
multiple servers if you have a private network between workers and the
database. I will presume you are setting up everything on a single host. A
multi-host setup is out of scope for these instructions and should only be done
if you really understand the workings of Redis, Postgresql and Django.


We'll run all three states in succession and turn on debugging, so you can see
what salt is doing in the background:

    salt-call -l debug state.sls armada.stationspinner.database
    salt-call -l debug state.sls armada.stationspinner.worker
    salt-call -l debug state.sls armada.stationspinner.api
  
This will install and configure everything. The worker state also start a task
called "universe.update_universe" that fetches all api call types, sovereignty
and such. This task has to finish before we can add API keys, but we will get
to that later.

Next, we'll create an admin user for you to log in with:

    su - stationspinner
    cd /srv/www/stationspinner
    source env/bin/activate
    cd web
    python manage.py createsuperuser 

Use the same parameters as you gave for admins in the configuration. This can
be done automatically, but it would mean putting in your password in clear text
in the config. After all this is done, exit the shell and get back to being
root:

    exit

Installing armada
=================

Now we will setup the web server and bootstrap the armada angularjs frontend:

    salt-call -l debug state.sls armada.armada
    
This installs nodejs, npm and clones the armada repository. Bower installs all
dependencies, then nginx is configured and started. You should now be able to
open armada in your browser:

http://hostname/

or whicever hostname or IP you used.

Using armada
============

Hopefully, the bootstrapping of stationspinner has finished in the background
while you've installed armada. You can keep a tail going on the worker log
which is located here:

    tail -f /srv/www/stationspinner/log/celery-stationspinner1.log

As long as "universe.fetch_apicalls" has finished, you should be good.

Log in with the admin user you created and go to settings->API keys. Add some
keys with at least charactersheets or preferably everything. They should be
indexed promptly and you should see it in the worker log after you've saved it.
They should now show up in the dashboard.
