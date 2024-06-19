#!/bin/bash

# Установим переменные.
PROMETHEUS_VERSION="2.51.1"
PROMETHEUS_URL="https://github.com/prometheus/prometheus/releases/download/v$PROMETHEUS_VERSION/prometheus-$PROMETHEUS_VERSION.linux-amd64.tar.gz"
PROMETHEUS_FOLDER_CONFIG="/etc/prometheus"
PROMETHEUS_FOLDER_TSDATA="/var/lib/prometheus"

# Переменная определения и хранения дистрибутива:
OS=$(awk -F= '/^ID=/{gsub(/"/, "", $2); print $2}' /etc/os-release)

# Выбор ОС для установки необходимых пакетов и настройки firewall..
check_os() {
  if [ "$OS" == "ubuntu" ]; then
      packages_firewall_ubuntu
  elif [ "$OS" == "almalinux" ]; then
      packages_firewall_almalinux
  else
      echo "Скрипт не поддерживает установленную ОС: $OS"
      # Выход из скрипта с кодом 1.
      exit 1
  fi
}

# Функция установки необходимых пакетов и настройки firewall на Ubuntu:
packages_firewall_ubuntu() {
  sudo apt update
  sudo apt -y install wget tar
}

# Функция установки необходимых пакетов и настройки firewall на AlmaLinux:
packages_firewall_almalinux() {
  sudo dnf -y update
  sudo dnf -y install wget tar
  sudo firewall-cmd --permanent --add-port=9090/tcp
  sudo firewall-cmd --reload
}

# Функция настройки firewall:
setting() {
  firewall-cmd --permanent --add-port=9090/tcp
  firewall-cmd --reload
}

# Функция подготовки почвы:
preparation() {
  sudo mkdir -p $PROMETHEUS_FOLDER_CONFIG $PROMETHEUS_FOLDER_TSDATA
  sudo useradd --no-create-home --shell /bin/false prometheus
}

# Функция для скачивания Prometheus:
download_prometheus () {
  sudo wget $PROMETHEUS_URL -O /tmp/prometheus.tar.gz
  sudo tar -xzf /tmp/prometheus.tar.gz -C /tmp
  sudo mv /tmp/prometheus-$PROMETHEUS_VERSION.linux-amd64/* /etc/prometheus
  sudo mv /etc/prometheus/prometheus /usr/bin/
  sudo rm -rf /tmp/prometheus* 
  sudo chown -R prometheus:prometheus $PROMETHEUS_FOLDER_CONFIG
  sudo chown prometheus:prometheus /usr/bin/prometheus
  sudo chown prometheus:prometheus $PROMETHEUS_FOLDER_TSDATA
}

# Функция создания конфиг файла Prometheus:
create_prometheus_config() {
  sudo tee $PROMETHEUS_FOLDER_CONFIG/prometheus.yml > /dev/null <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "Prometheus server"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "Linux Node Exporter"
    static_configs:
      - targets:
        - 10.100.10.1:9100
        - 10.100.10.2:9100

  - job_name: "Windows Node Exporter"
    static_configs:
      - targets:
        - 10.100.10.3:9182
        - 10.100.10.4:9182
EOF
}

# Функция создания юнита Prometheus для systemd:
create_unit_prometheus() {
  sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOF
[Unit]
Description=Prometheus Server
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
Restart=on-failure
ExecStart=/usr/bin/prometheus \
  --config.file       ${PROMETHEUS_FOLDER_CONFIG}/prometheus.yml \
  --storage.tsdb.path ${PROMETHEUS_FOLDER_TSDATA}

[Install]
WantedBy=multi-user.target
EOF
}

# Запуск и включение Prometheus:
start_enable_prometheus() {
  sudo systemctl daemon-reload
  sudo systemctl start prometheus
  sudo systemctl enable prometheus
}

# Функция отключения SELinux:
disable_selinux() {
  # Проверка, существует ли файл конфигурации SELinux
  if [ -f /etc/selinux/config ]; then
    # Изменение строки SELINUX= на SELINUX=disabled
    sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config  
    echo "SELinux был отключен. Перезагрузите систему для применения изменений."
  else
    echo "Файл конфигурации SELinux не найден."
  fi
}

# Функция проверки состояния Prometheus:
check_status_prometheus() {
  sudo systemctl status prometheus --no-pager
  prometheus --version
  echo "Prometheus успешно установлен и настроен на $OS."
}

# Создание функций main
main() {
  check_os
  preparation
  download_prometheus
  create_prometheus_config
  create_unit_prometheus
  start_enable_prometheus
  disable_selinux
  check_status_prometheus
}

# Вызов функции main
main

