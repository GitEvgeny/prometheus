#!/bin/bash

# Установим переменные.
# Переменная для хранения версии Prometheus:
PROMETHEUS_VERSION="2.51.1"
# Переменная для хранения URL сайта GitHub Prometheus для скачивания:
PROMETHEUS_URL="https://github.com/prometheus/prometheus/releases/download/v$PROMETHEUS_VERSION/prometheus-$PROMETHEUS_VERSION.linux-amd64.tar.gz"
# Переменная для хранения директории конфигов Prometheus:
PROMETHEUS_FOLDER_CONFIG="/etc/prometheus"
# Переменная для хранения директории БД Prometheus:
PROMETHEUS_FOLDER_TSDATA="/var/lib/prometheus"
# Переменная определения и хранения дистрибутива:
OS=$(awk -F= '/^ID=/{gsub(/"/, "", $2); print $2}' /etc/os-release)

# Выбор ОС для установки необходимых пакетов для Prometheus.
check_os() {
  if [ "$OS" == "ubuntu" ]; then
      installing_packages_ubuntu
  elif [ "$OS" == "almalinux" ]; then
      installing_packages_almalinux
  else
      echo "Скрипт не поддерживает установленную ОС: $OS"
      # Выход из скрипта с кодом 1.
      exit 1
  fi
}

# Функция установки необходимых пакетов для Prometheus на Ubuntu:
installing_packages_ubuntu() {
  # Обновить список доступных пакетов.
  sudo apt update
  # Установить wget и tar.
  sudo apt -y install wget tar
}

# Функция установки необходимых пакетов для Prometheus на AlmaLinux:
installing_packages_almalinux() {
  # Обновить список доступных пакетов.
  sudo dnf -y update
  # Установить wget и tar.
  sudo dnf -y install wget tar
}

# Функция подготовки почвы:
preparation() {
  # Создание необходимых директорий:
  sudo mkdir -p $PROMETHEUS_FOLDER_CONFIG $PROMETHEUS_FOLDER_TSDATA
  # Создание пользователя prometheus:
  sudo useradd --no-create-home --shell /bin/false prometheus
}

# Функция для скачивания Prometheus:
download_prometheus () {
  # Скачивание Prometheus с указанным именем:
  wget $PROMETHEUS_URL -O /tmp/prometheus.tar.gz
  # Распаковка Prometheus в директорию /tmp:
  tar -xzf /tmp/prometheus.tar.gz -C /tmp
  # Перемещение всех файлов Prometheus:
  sudo mv /tmp/prometheus-$PROMETHEUS_VERSION.linux-amd64/* /etc/prometheus
  # Перемещение исполняемого файла Prometheus:
  sudo mv /etc/prometheus/prometheus /usr/bin/
  # Удаление директорий prometheus:
  sudo rm -rf /tmp/prometheus* 
  # Настройка прав:
  sudo chown -R prometheus:prometheus $PROMETHEUS_FOLDER_CONFIG
  sudo chown prometheus:prometheus /usr/bin/prometheus
  sudo chown prometheus:prometheus $PROMETHEUS_FOLDER_TSDATA
}

# Функция создания конфиг файла Prometheus:
create_prometheus_config() {
  sudo tee $PROMETHEUS_FOLDER_CONFIG/prometheus.yml > /dev/null <<EOF
# Определяет глобальные настройки для Prometheus. Эти настройки применяются ко всем заданиям (jobs), если не переопределены локально.
global:
  # Устанавливает интервал опроса (scrape) для всех заданий по умолчанию. В данном случае, Prometheus будет опрашивать все цели каждые 15 секунд.
  scrape_interval: 15s

# Определяет список конфигураций для опроса целей. Каждая конфигурация описывает одно или несколько заданий опроса.
scrape_configs:
  # Указывает имя задания. Это имя используется для идентификации задания в метриках и логах Prometheus.
  - job_name: "prometheus"
    # Определяет статические конфигурации для целей опроса. В данном случае используются статические IP-адреса или хосты.
    static_configs:
      # Определяет список целей для опроса. В данном случае Prometheus будет опрашивать сам себя по адресу localhost:9090.
      - targets: ["localhost:9090"]

  - job_name: "Linux Node Exporter"
    static_configs:
      # Начало списка целей для опроса.
      - targets:
        # Определяет первую цель для опроса. В данном случае это узел с IP-адресом 10.100.10.1 и портом 9100.
        - 10.100.10.1:9100
        # Определяет вторую цель для опроса. В данном случае это узел с IP-адресом 10.100.10.2 и портом 9100.
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
# Описание юнита.
Description=Prometheus Server
# Указывает, что служба Prometheus "хочет" (Wants) зависеть от network-online.target. Это означает, что служба
# будет пытаться запуститься после того, как сеть будет доступна, но не будет блокировать загрузку, если сеть не доступна.
Wants=network-online.target
# Указывает, что служба Prometheus должна запускаться после network-online.target. Это гарантирует,
# что служба запустится только после того, как сеть будет доступна.
After=network-online.target

[Service]
# Указывает пользователя, от имени которого будет запущена служба.
User=prometheus
# Указывает группу, от имени которой будет запущена служба.
Group=prometheus
# Указывает тип службы. В данном случае это simple, что означает, что процесс, указанный в ExecStart,
# будет основным процессом службы. Systemd считает службу запущенной, как только этот процесс будет запущен.
Type=simple
# Указывает, что служба должна автоматически перезапускаться в случае сбоя. Это помогает обеспечить высокую доступность службы.
Restart=on-failure
# Указывает команду для запуска службы. В данном случае это команда для запуска Prometheus с указанием конфигурационного файла и пути для хранения БД.
ExecStart=/usr/bin/prometheus \
  --config.file       ${PROMETHEUS_FOLDER_CONFIG}/prometheus.yml \
  --storage.tsdb.path ${PROMETHEUS_FOLDER_TSDATA}

[Install]
# Указывает, что служба должна быть запущена при достижении multi-user.target. Это стандартный уровень запуска для большинства систем,
# который включает в себя все службы, необходимые для работы в многопользовательском режиме без графического интерфейса.
# Это позволяет службе автоматически запускаться при загрузке системы в многопользовательский режим.
WantedBy=multi-user.target
EOF
}

# Запуск и включение Prometheus:
start_enable_prometheus() {
  # Перезапуск все сервисов.
  sudo systemctl daemon-reload
  # Запуск Prometheus.
  sudo systemctl start prometheus
  # Добавление в автозапуск Prometheus.
  sudo systemctl enable prometheus
}

# Функция проверки наличия SELinux:
check_selinux() {
  # Данная проверка необходима для Almalinux, т.к. там по умолчанию SELinux установлен и включен.
  # И SELinux мешает работе Prometheus, чтобы не было ошибок проходим проверку и отключаем:
  if sestatus &> /dev/null; then
    echo "SELinux установлен и активен в системе."
    # Переключить режим SELinux на: Permissive (Разрешающий)
    sudo setenforce 0
    # Перезапуск Prometheus.
    sudo systemctl restart prometheus
    echo "SELinux переведён в режим: Permissive (Разрешающий)."
    else
    echo "SELinux не установлен или не активен в системе."
  fi
}

# Функция проверки состояния Prometheus:
check_status_prometheus() {
  # Проверить статус работы:
  sudo systemctl status prometheus --no-pager
  # Вывести версию:
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
  check_selinux
  check_status_prometheus
}

# Вызов функции main
main

