FROM debian:stretch

RUN echo "#Debian 9 (Stretch) \n\
deb http://archive.debian.org/debian/ stretch main contrib non-free \n\
\n\
deb http://archive.debian.org/debian/ stretch-proposed-updates main contrib non-free \n\
\n\
deb http://archive.debian.org/debian-security stretch/updates main contrib non-free " > /etc/apt/sources.list

RUN apt-get update && apt-get -y upgrade && apt-get -y dist-upgrade && apt-get -y autoremove
RUN apt-get update && apt-get -y install postgresql-9.6-postgis-2.3 postgresql-contrib-9.6 git vim wget curl screen osm2pgsql autoconf libtool libmapnik-dev apache2-dev unzip gdal-bin mapnik-utils node-carto apache2 gosu php  && apt-get clean

RUN sed -i 's/max_connections = 100/max_connections = 1000/g' /etc/postgresql/9.6/main/postgresql.conf
RUN useradd -m -p osm osm
RUN sed -i 's/\/home\/osm:/\/home\/osm:\/bin\/bash/g' /etc/passwd
RUN cp -pr /var/lib/postgresql/9.6/main /var/lib/postgresql/9.6/main_bak

COPY mod_tile-0.5.tgz /home/osm/
RUN cd /home/osm && tar -xvzf mod_tile-0.5.tgz
RUN cd /home/osm/mod_tile-0.5 && ./autogen.sh && ./configure && make && make install && cp debian/renderd.init /etc/init.d/renderd

COPY v2.29.1.tgz /home/osm/
RUN cd /home/osm && tar -xvzf v2.29.1.tgz 
RUN cd /home/osm/openstreetmap-carto-2.29.1 && sed -i 's/"dbname": "gis"/"dbname": "world"/' project.mml 
RUN cd /home/osm/openstreetmap-carto-2.29.1 && carto project.mml > style.xml

RUN sed -i 's/URI=\/osm_tiles\//URI=\//g' /usr/local/etc/renderd.conf && sed -i 's/XML=\/home\/jburgess\/osm\/svn\.openstreetmap\.org\/applications\/rendering\/mapnik\/osm\-local\.xml/XML=\/home\/osm\/openstreetmap-carto-2.29.1\/style.xml/' /usr/local/etc/renderd.conf && sed -i 's/HOST=tile\.openstreetmap\.org/HOST=localhost/' /usr/local/etc/renderd.conf && sed -i 's/plugins_dir=\/usr\/lib\/mapnik\/input/plugins_dir=\/usr\/lib\/mapnik\/3.0\/input\//' /usr/local/etc/renderd.conf && cat /usr/local/etc/renderd.conf | grep -v ';' > /usr/local/etc/renderd.conf.new && mv /usr/local/etc/renderd.conf /usr/local/etc/renderd.conf.bak && mv /usr/local/etc/renderd.conf.new /usr/local/etc/renderd.conf && chmod a+x /etc/init.d/renderd && sed -i 's/DAEMON=\/usr\/bin\/$NAME/DAEMON=\/usr\/local\/bin\/$NAME/' /etc/init.d/renderd && sed -i 's/DAEMON_ARGS=""/DAEMON_ARGS=" -c \/usr\/local\/etc\/renderd.conf"/' /etc/init.d/renderd && sed -i 's/RUNASUSER=www-data/RUNASUSER=osm/' /etc/init.d/renderd && ln -s /usr/local/etc/renderd.conf /etc/renderd.conf

RUN mkdir -p /var/lib/mod_tile/default && chown osm:osm -R /var/lib/mod_tile && chmod 777 /var/lib/mod_tile/default

RUN echo "LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so" > /etc/apache2/mods-available/tile.load && ln -s /etc/apache2/mods-available/tile.load /etc/apache2/mods-enabled/
RUN cp /home/osm/mod_tile-0.5/src/.libs/mod_tile.so /usr/lib/apache2/modules/mod_tile.so && ldconfig -v
RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf
RUN echo "<VirtualHost *:80> \n\
        ServerAdmin webmaster@localhost \n\
        DocumentRoot /var/www/html \n\
        ErrorLog /var/log/apache2/error.log \n\
        CustomLog /var/log/apache2/access.log combined \n\
        LoadTileConfigFile /usr/local/etc/renderd.conf \n\
        ModTileRenderdSocketName /var/run/renderd/renderd.sock \n\
        ModTileRequestTimeout 0 \n\
        ModTileMissingRequestTimeout 30 \n\
</VirtualHost>" > /etc/apache2/sites-enabled/000-default.conf

COPY leaflet.css /var/www/html/
COPY leaflet.js /var/www/html/
COPY index.php /var/www/html/
RUN rm /var/www/html/index.html

RUN service renderd restart
RUN service apache2 restart

ADD entrypoint.sh /root/entrypoint.sh
RUN chmod 755 /root/entrypoint.sh
CMD /root/entrypoint.sh
