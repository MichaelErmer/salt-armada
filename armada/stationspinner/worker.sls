{% set stationspinner = salt["pillar.get"]("stationspinner", {}) %}
{% set db = salt["pillar.get"]("postgres", {}) %}
include:
  - .base

# Celery configuration

celery dist:
  pkg.installed:
    - name: celeryd

celery logdir:
  file.directory:
    - name: /srv/www/stationspinner/log
    - makedirs: True
    - user: stationspinner
    - group: celery
    - mode: 775

celery rundir:
  file.directory:
    - name: /srv/www/stationspinner/run
    - user: stationspinner
    - group: celery
    - mode: 775

celeryd config:
  file.managed:
    - name: /etc/default/stationspinner-worker
    - source: salt://armada/stationspinner/files/stationspinner-worker.conf
    - require:
      - pkg: celery dist

celerybeat config:
  file.managed:
    - name: /etc/default/stationspinner-beat
    - source: salt://armada/stationspinner/files/stationspinner-beat.conf
    - require:
      - pkg: celery dist

celeryd initscript:
  file.managed:
    - name: /etc/init.d/stationspinner-worker
    - source: salt://armada/stationspinner/files/stationspinner-worker.init
    - mode: 755
    - require:
      - file: celeryd config

celerybeat initscript:
  file.managed:
    - name: /etc/init.d/stationspinner-beat
    - source: salt://armada/stationspinner/files/stationspinner-beat.init
    - mode: 755
    - require:
      - file: celerybeat config


{% if not stationspinner.debug %}
celeryd service:
  service.running:
    - name: stationspinner-worker
    - enable: True
    - running: True
    - require:
      - file: celeryd initscript
      - file: celery rundir
      - file: celery logdir

manual restart celeryd:
  cmd.wait:
    - name: service stationspinner-worker restart
    - watch:
      - git: stationspinner code

celerybeat service:
  service.running:
    - name: stationspinner-beat
    - enable: True
    - running: True
    - require:
      - file: celerybeat initscript
      - file: celery rundir
      - file: celery logdir

manual restart beat:
  cmd.wait:
    - name: service stationspinner-beat stop; service stationspinner-beat start
    - watch:
      - git: stationspinner code

{% endif %}

bootstrap universe:
  cmd.run: 
    - name: 'source ../env/bin/activate; python manage.py bootstrap'
    - user: stationspinner
    - shell: /bin/bash
    - cwd: '/srv/www/stationspinner/web'

{% for market in stationspinner.markets %}
{{ market }} market indexing:
  cmd.run: 
    - name: 'source ../env/bin/activate; python manage.py addmarket "{{ market }}"'
    - user: stationspinner
    - shell: /bin/bash
    - cwd: '/srv/www/stationspinner/web'
{% endfor %}

