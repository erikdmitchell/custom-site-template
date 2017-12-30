#!/usr/bin/env bash
# Provision WordPress Stable

DOMAIN=`get_primary_host "${VVV_SITE_NAME}".test`
DOMAINS=`get_hosts "${DOMAIN}"`
SITE_TITLE=`get_config_value 'site_title' "${DOMAIN}"`
WP_VERSION=`get_config_value 'wp_version' 'latest'`
WP_TYPE=`get_config_value 'wp_type' "single"`
DB_NAME=`get_config_value 'db_name' "${VVV_SITE_NAME}"`
DB_NAME=${DB_NAME//[\\\/\.\<\>\:\"\'\|\?\!\*-]/}

DELETE_DEFAULT_PLUGINS=`get_config_value 'delete_default_plugins' "false"`
DELETE_DEFAULT_THEMES=`get_config_value 'delete_default_themes' "false"`
WP_CONTENT=`get_config_value 'wp_content' "false"`
PLUGINS=(`cat ${VVV_CONFIG} | shyaml get-values sites.${SITE_ESCAPED}.custom.plugins 2> /dev/null`)
THEMES=(`cat ${VVV_CONFIG} | shyaml get-values sites.${SITE_ESCAPED}.custom.themes 2> /dev/null`)

# Make a database, if we don't already have one
echo -e "\nCreating database '${DB_NAME}' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO wp@localhost IDENTIFIED BY 'wp';"
echo -e "\n DB operations done.\n\n"

# Nginx Logs
mkdir -p ${VVV_PATH_TO_SITE}/log
touch ${VVV_PATH_TO_SITE}/log/error.log
touch ${VVV_PATH_TO_SITE}/log/access.log

# Install and configure the latest stable version of WordPress
if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-load.php" ]]; then
    echo "Downloading WordPress..."
	noroot wp core download --version="${WP_VERSION}"
fi

if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-config.php" ]]; then
  echo "Configuring WordPress Stable..."
  noroot wp core config --dbname="${DB_NAME}" --dbuser=wp --dbpass=wp --quiet --extra-php <<PHP
define( 'WP_DEBUG', true );
define( 'WP_DEBUG_DISPLAY', false );
define( 'WP_DEBUG_LOG', true );
define( 'SCRIPT_DEBUG', true );
PHP
fi

if ! $(noroot wp core is-installed); then
  echo "Installing WordPress Stable..."

  if [ "${WP_TYPE}" = "subdomain" ]; then
    INSTALL_COMMAND="multisite-install --subdomains"
  elif [ "${WP_TYPE}" = "subdirectory" ]; then
    INSTALL_COMMAND="multisite-install"
  else
    INSTALL_COMMAND="install"
  fi

  noroot wp core ${INSTALL_COMMAND} --url="${DOMAIN}" --quiet --title="${SITE_TITLE}" --admin_name=admin --admin_email="admin@local.test" --admin_password="password"
  
  # Remove default plugins
  if [ "${DELETE_DEFAULT_PLUGINS}" != "false" ]; then
    echo -e "\nRemoving default plugins..."    
    noroot wp plugin uninstall hello akismet
  fi  
  
  # Remove default themes
  if [ "${DELETE_DEFAULT_THEMES}" != "false" ]; then  
    echo -e "\nRemoving default themes..."
    noroot wp theme uninstall twentyfifteen twentysixteen twentyseventeen
  fi

  # Import default content
  if [ "${WP_CONTENT}" != "false" ]; then  
    echo -e "\nImporting default content..."
    curl -s https://raw.githubusercontent.com/manovotny/wptest/master/wptest.xml > import.xml && noroot wp plugin install wordpress-importer --quiet && noroot wp plugin activate wordpress-importer --quiet && noroot wp import import.xml --authors=skip --quiet && rm import.xml
  fi  
  
  # Add plugins
  for i in "${PLUGINS[@]}"
    do :
      if [[ ! -d "${VVV_PATH_TO_SITE}/public_html/wp-content/plugins/$i" ]]; then
        echo "Installing plugin $i from wordpress.org..."
        noroot wp plugin install $i --quiet
      else
        echo "Updating plugin $i from wordpress.org..."
        noroot wp plugin update $i --quiet
      fi
  done
  
  # Add themes
  for k in "${THEMES[@]}"
    do :
      if [[ ! -d "${VVV_PATH_TO_SITE}/public_html/wp-content/themes/$k" ]]; then
        echo "Installing theme $k from wordpress.org..."
        noroot wp theme install $k --quiet
      else
        echo "Updating theme $k from wordpress.org..."
        noroot wp theme update $k --quiet
      fi
  done

else
  echo "Updating WordPress Stable..."
  cd ${VVV_PATH_TO_SITE}/public_html
  noroot wp core update --version="${WP_VERSION}" 
fi  

cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
sed -i "s#{{DOMAINS_HERE}}#${DOMAINS}#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
