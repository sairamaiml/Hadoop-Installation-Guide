#!/usr/bin/env bash
#
# Experiment 1 - Hadoop Pseudo-Distributed Mode Setup
# Ubuntu/Debian-based systems
#
# Installs/configures Java, SSH and Hadoop, configures HDFS/YARN,
# starts the daemons, and runs a basic HDFS test.
#
# Usage:
#   chmod +x setup_hadoop_ex1.sh
#   ./setup_hadoop_ex1.sh
#
# Notes:
# - Run as a normal user with sudo access. Do NOT run the whole script as root.
# - This script uses the current user's HOME automatically.
# - It is designed for a single-machine pseudo-distributed Hadoop lab setup.
# - It intentionally does NOT configure a fully distributed cluster.
#

set -Eeuo pipefail

# -----------------------------
# Configuration
# -----------------------------
HADOOP_VERSION="${HADOOP_VERSION:-3.4.2}"
HADOOP_INSTALL_DIR="${HADOOP_INSTALL_DIR:-/opt/hadoop}"
JAVA_PACKAGE="${JAVA_PACKAGE:-openjdk-11-jdk}"
HADOOP_MIRROR_BASE="https://archive.apache.org/dist/hadoop/common"
HADOOP_TARBALL="hadoop-${HADOOP_VERSION}.tar.gz"
HADOOP_URL="${HADOOP_MIRROR_BASE}/hadoop-${HADOOP_VERSION}/${HADOOP_TARBALL}"

HADOOP_DATA_DIR="${HOME}/hadoop_data"
HADOOP_LOG_DIR="${HOME}/hadoop_logs"
HADOOP_TMP_DIR="${HOME}/hadoop_tmp"

SCRIPT_NAME="$(basename "$0")"
START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

# -----------------------------
# Formatting
# -----------------------------
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
green()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }
red()    { printf '\033[1;31m%s\033[0m\n' "$*"; }
blue()   { printf '\033[1;34m%s\033[0m\n' "$*"; }

step() {
    echo
    bold "============================================================"
    bold "$*"
    bold "============================================================"
}

die() {
    red "ERROR: $*"
    echo
    red "The script stopped to avoid continuing with a broken configuration."
    red "Read the suggested fix above, correct the issue, then run:"
    red "  ./${SCRIPT_NAME}"
    exit 1
}

on_error() {
    local line="$1"
    local cmd="$2"
    echo
    red "============================================================"
    red "SETUP FAILED"
    red "============================================================"
    red "Line : ${line}"
    red "Command: ${cmd}"
    echo
    yellow "Useful diagnostics:"
    command -v java >/dev/null 2>&1 && java -version 2>&1 || true
    command -v hadoop >/dev/null 2>&1 && hadoop version 2>&1 || true
    command -v jps >/dev/null 2>&1 && jps 2>&1 || true
    echo
    yellow "Suggested actions:"
    yellow "1. Read the error immediately above this message."
    yellow "2. If it is a network/download error, check your Internet connection and rerun."
    yellow "3. If it is a permission error, make sure this script is NOT being run as root and that your user has sudo access."
    yellow "4. If Hadoop is partially installed, rerunning this script is normally safe."
    exit 1
}
trap 'on_error "${LINENO}" "${BASH_COMMAND}"' ERR

# -----------------------------
# Basic checks
# -----------------------------
step "1/10 - Checking system"

if [[ "${EUID}" -eq 0 ]]; then
    die "Do not run this script as root. Run it as your normal Ubuntu user with sudo access."
fi

if ! command -v sudo >/dev/null 2>&1; then
    die "sudo is not installed. Install sudo or use an Ubuntu installation with administrative access."
fi

if [[ ! -r /etc/os-release ]]; then
    die "Cannot identify the operating system."
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *"debian"* ]]; then
    yellow "Warning: This script was designed for Ubuntu/Debian-based systems."
    yellow "Detected: ${PRETTY_NAME:-unknown}"
    read -r -p "Continue anyway? [y/N] " answer
    [[ "${answer,,}" == "y" ]] || exit 0
fi

if ! ping -c 1 -W 2 archive.apache.org >/dev/null 2>&1; then
    yellow "Warning: archive.apache.org could not be reached by ping."
    yellow "Ping may be blocked on your network, so the script will continue and test HTTPS during download."
fi

ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
USERNAME="$(id -un)"
GROUPNAME="$(id -gn)"
JAVA_HOME_DETECTED=""

blue "User          : ${USERNAME}"
blue "Home          : ${HOME}"
blue "Architecture  : ${ARCH}"
blue "OS            : ${PRETTY_NAME:-unknown}"
blue "Hadoop        : ${HADOOP_VERSION}"
blue "Install dir   : ${HADOOP_INSTALL_DIR}"

# -----------------------------
# Dependencies
# -----------------------------
step "2/10 - Installing required packages"

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    "${JAVA_PACKAGE}" \
    openssh-client \
    openssh-server \
    wget \
    curl \
    tar \
    rsync \
    procps \
    net-tools

# Find JAVA_HOME without hardcoding a username/path.
if command -v java >/dev/null 2>&1; then
    JAVA_BIN="$(readlink -f "$(command -v java)")"
    JAVA_HOME_DETECTED="$(dirname "$(dirname "${JAVA_BIN}")")"
fi

[[ -n "${JAVA_HOME_DETECTED}" && -x "${JAVA_HOME_DETECTED}/bin/java" ]] || \
    die "Java was installed but JAVA_HOME could not be detected."

blue "JAVA_HOME detected as: ${JAVA_HOME_DETECTED}"
java -version

# -----------------------------
# SSH
# -----------------------------
step "3/10 - Configuring SSH"

sudo systemctl enable --now ssh 2>/dev/null || \
sudo systemctl enable --now sshd 2>/dev/null || \
die "Could not start the SSH service. Try: sudo systemctl status ssh"

mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"

if [[ ! -f "${HOME}/.ssh/id_rsa" ]]; then
    ssh-keygen -t rsa -b 3072 -N "" -f "${HOME}/.ssh/id_rsa"
else
    blue "Existing SSH RSA key found; keeping it."
fi

touch "${HOME}/.ssh/authorized_keys"
chmod 600 "${HOME}/.ssh/authorized_keys"

if ! grep -Fqx "$(cat "${HOME}/.ssh/id_rsa.pub")" "${HOME}/.ssh/authorized_keys"; then
    cat "${HOME}/.ssh/id_rsa.pub" >> "${HOME}/.ssh/authorized_keys"
fi

# Avoid interactive host-key confirmation for localhost.
mkdir -p "${HOME}/.ssh"
touch "${HOME}/.ssh/known_hosts"
chmod 644 "${HOME}/.ssh/known_hosts"

ssh-keyscan -H localhost 2>/dev/null >> "${HOME}/.ssh/known_hosts" || true
ssh-keyscan -H 127.0.0.1 2>/dev/null >> "${HOME}/.ssh/known_hosts" || true
sort -u "${HOME}/.ssh/known_hosts" -o "${HOME}/.ssh/known_hosts"

if ! ssh -o BatchMode=yes -o ConnectTimeout=5 localhost "echo SSH_OK" 2>/dev/null | grep -q "SSH_OK"; then
    die "Passwordless SSH to localhost failed.

Try manually:
  ssh localhost

If it asks for a password, fix ~/.ssh/authorized_keys permissions and SSH configuration, then rerun the script."
fi

green "Passwordless SSH to localhost works."

# -----------------------------
# Download / install Hadoop
# -----------------------------
step "4/10 - Downloading and installing Hadoop ${HADOOP_VERSION}"

TMP_INSTALL_DIR="$(mktemp -d)"
cleanup_tmp() { rm -rf "${TMP_INSTALL_DIR}"; }
trap cleanup_tmp EXIT

if [[ -x "${HADOOP_INSTALL_DIR}/bin/hadoop" ]] && \
   "${HADOOP_INSTALL_DIR}/bin/hadoop" version 2>/dev/null | grep -q "Hadoop ${HADOOP_VERSION}"; then
    blue "Hadoop ${HADOOP_VERSION} is already installed at ${HADOOP_INSTALL_DIR}."
else
    wget --https-only --timeout=30 --tries=3 -O \
        "${TMP_INSTALL_DIR}/${HADOOP_TARBALL}" \
        "${HADOOP_URL}" || \
        die "Could not download Hadoop ${HADOOP_VERSION}.

Check your Internet connection. If Apache has moved/removed this archive version, rerun with another version, for example:
  HADOOP_VERSION=3.4.1 ./${SCRIPT_NAME}"

    tar -xzf "${TMP_INSTALL_DIR}/${HADOOP_TARBALL}" -C "${TMP_INSTALL_DIR}"

    EXTRACTED_DIR="${TMP_INSTALL_DIR}/hadoop-${HADOOP_VERSION}"
    [[ -d "${EXTRACTED_DIR}" ]] || die "Hadoop archive extracted, but the expected directory was not found."

    sudo mkdir -p "$(dirname "${HADOOP_INSTALL_DIR}")"

    # Preserve a previous installation rather than deleting it.
    if [[ -d "${HADOOP_INSTALL_DIR}" ]]; then
        BACKUP_DIR="${HADOOP_INSTALL_DIR}.backup.$(date +%Y%m%d%H%M%S)"
        yellow "Existing Hadoop directory found. Moving it to ${BACKUP_DIR}"
        sudo mv "${HADOOP_INSTALL_DIR}" "${BACKUP_DIR}"
    fi

    sudo mv "${EXTRACTED_DIR}" "${HADOOP_INSTALL_DIR}"
fi

sudo chown -R root:root "${HADOOP_INSTALL_DIR}"
[[ -x "${HADOOP_INSTALL_DIR}/bin/hadoop" ]] || \
    die "Hadoop installation is incomplete: ${HADOOP_INSTALL_DIR}/bin/hadoop was not found."

# -----------------------------
# Environment
# -----------------------------
step "5/10 - Configuring environment variables"

BASHRC="${HOME}/.bashrc"
ENV_START="# >>> Hadoop Lab Environment >>>"
ENV_END="# <<< Hadoop Lab Environment <<<"

# Remove an old block from this script, if present.
if grep -qF "${ENV_START}" "${BASHRC}" 2>/dev/null; then
    awk -v start="${ENV_START}" -v end="${ENV_END}" '
        $0 == start {skip=1; next}
        $0 == end {skip=0; next}
        !skip {print}
    ' "${BASHRC}" > "${BASHRC}.hadoop.tmp"
    mv "${BASHRC}.hadoop.tmp" "${BASHRC}"
fi

cat >> "${BASHRC}" <<EOF

${ENV_START}
export JAVA_HOME="${JAVA_HOME_DETECTED}"
export HADOOP_HOME="${HADOOP_INSTALL_DIR}"
export HADOOP_HDFS_HOME="\$HADOOP_HOME"
export HADOOP_COMMON_HOME="\$HADOOP_HOME"
export HADOOP_MAPRED_HOME="\$HADOOP_HOME"
export HADOOP_YARN_HOME="\$HADOOP_HOME"
export YARN_HOME="\$HADOOP_HOME"
export PATH="\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin"
${ENV_END}
EOF

export JAVA_HOME="${JAVA_HOME_DETECTED}"
export HADOOP_HOME="${HADOOP_INSTALL_DIR}"
export HADOOP_HDFS_HOME="${HADOOP_HOME}"
export HADOOP_COMMON_HOME="${HADOOP_HOME}"
export HADOOP_MAPRED_HOME="${HADOOP_HOME}"
export HADOOP_YARN_HOME="${HADOOP_HOME}"
export YARN_HOME="${HADOOP_HOME}"
export PATH="${PATH}:${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin"

# -----------------------------
# Hadoop directories
# -----------------------------
step "6/10 - Creating Hadoop data/log directories"

mkdir -p \
    "${HADOOP_DATA_DIR}/namenode" \
    "${HADOOP_DATA_DIR}/datanode" \
    "${HADOOP_LOG_DIR}" \
    "${HADOOP_TMP_DIR}"

chmod 755 "${HADOOP_DATA_DIR}" "${HADOOP_LOG_DIR}" "${HADOOP_TMP_DIR}"

# -----------------------------
# Hadoop configuration
# -----------------------------
step "7/10 - Writing Hadoop configuration"

CONF_DIR="${HADOOP_HOME}/etc/hadoop"

[[ -d "${CONF_DIR}" ]] || die "Hadoop configuration directory not found: ${CONF_DIR}"

# Backup configuration once per run.
BACKUP_CONF="${HOME}/hadoop_config_backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "${BACKUP_CONF}"
cp -a "${CONF_DIR}/." "${BACKUP_CONF}/"
blue "Original Hadoop configuration backed up to: ${BACKUP_CONF}"

# hadoop-env.sh
sed -i '/^[[:space:]]*export JAVA_HOME=/d' "${CONF_DIR}/hadoop-env.sh"
cat >> "${CONF_DIR}/hadoop-env.sh" <<EOF
export JAVA_HOME="${JAVA_HOME_DETECTED}"
EOF

# core-site.xml
cat > "${CONF_DIR}/core-site.xml" <<EOF
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://localhost:9000</value>
    </property>
</configuration>
EOF

# hdfs-site.xml
cat > "${CONF_DIR}/hdfs-site.xml" <<EOF
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>1</value>
    </property>

    <property>
        <name>dfs.namenode.name.dir</name>
        <value>file://${HADOOP_DATA_DIR}/namenode</value>
    </property>

    <property>
        <name>dfs.datanode.data.dir</name>
        <value>file://${HADOOP_DATA_DIR}/datanode</value>
    </property>
</configuration>
EOF

# mapred-site.xml
if [[ ! -f "${CONF_DIR}/mapred-site.xml.template" ]]; then
    die "mapred-site.xml.template is missing from ${CONF_DIR}."
fi

cat > "${CONF_DIR}/mapred-site.xml" <<EOF
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
</configuration>
EOF

# yarn-site.xml
cat > "${CONF_DIR}/yarn-site.xml" <<EOF
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>

    <property>
        <name>yarn.nodemanager.env-whitelist</name>
        <value>JAVA_HOME,HADOOP_HOME,HADOOP_COMMON_HOME,HADOOP_HDFS_HOME,HADOOP_MAPRED_HOME,HADOOP_YARN_HOME,HADOOP_CONF_DIR,CLASSPATH_PREPEND_DISTCACHE</value>
    </property>
</configuration>
EOF

# workers file for single-node setup
printf 'localhost\n' > "${CONF_DIR}/workers"

# Hadoop logs under the user's home, avoiding root-owned logs.
export HADOOP_LOG_DIR="${HADOOP_LOG_DIR}"

green "Hadoop configuration written."

# -----------------------------
# Validate installation
# -----------------------------
step "8/10 - Validating Hadoop installation"

"${HADOOP_HOME}/bin/hadoop" version
"${HADOOP_HOME}/bin/hdfs" getconf -confKey fs.defaultFS

# -----------------------------
# Format NameNode
# -----------------------------
step "9/10 - Formatting NameNode and starting services"

# If an existing HDFS is detected, do NOT silently destroy it.
if find "${HADOOP_DATA_DIR}/namenode" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
    yellow "An existing NameNode directory was detected."
    yellow "The script will NOT format it automatically because formatting destroys the existing HDFS namespace."
    yellow "If this is a fresh lab setup and you want to start over, remove:"
    yellow "  ${HADOOP_DATA_DIR}/namenode"
    yellow "then rerun this script."
else
    "${HADOOP_HOME}/bin/hdfs" namenode -format -force
fi

# Stop old services if they happen to be running.
"${HADOOP_HOME}/sbin/stop-yarn.sh" >/dev/null 2>&1 || true
"${HADOOP_HOME}/sbin/stop-dfs.sh" >/dev/null 2>&1 || true
sleep 2

"${HADOOP_HOME}/sbin/start-dfs.sh"
sleep 3
"${HADOOP_HOME}/sbin/start-yarn.sh"
sleep 5

# Verify processes.
JPS_OUTPUT="$(jps 2>&1 || true)"
echo "${JPS_OUTPUT}"

for daemon in NameNode DataNode SecondaryNameNode ResourceManager NodeManager; do
    if ! grep -q "${daemon}" <<< "${JPS_OUTPUT}"; then
        yellow "Warning: ${daemon} was not detected by jps."
    fi
done

if ! grep -q "NameNode" <<< "${JPS_OUTPUT}" || \
   ! grep -q "DataNode" <<< "${JPS_OUTPUT}"; then
    echo
    red "HDFS did not start correctly."
    yellow "Check the Hadoop logs:"
    yellow "  ls -lt ${HADOOP_LOG_DIR}"
    yellow "  tail -n 50 ${HADOOP_LOG_DIR}/*namenode*.log"
    yellow "  tail -n 50 ${HADOOP_LOG_DIR}/*datanode*.log"
    exit 1
fi

# -----------------------------
# HDFS functional test
# -----------------------------
step "10/10 - Running HDFS functional test"

TEST_DIR="/experiment1_test"
TEST_FILE="hadoop_test.txt"
TEST_LOCAL="${HADOOP_TMP_DIR}/${TEST_FILE}"

# Clean only our own test directory.
"${HADOOP_HOME}/bin/hdfs" dfs -rm -r -f "${TEST_DIR}" >/dev/null 2>&1 || true

"${HADOOP_HOME}/bin/hdfs" dfs -mkdir -p "${TEST_DIR}"
printf 'Hello Hadoop - Experiment 1\n' > "${TEST_LOCAL}"
"${HADOOP_HOME}/bin/hdfs" dfs -put -f "${TEST_LOCAL}" "${TEST_DIR}/"
"${HADOOP_HOME}/bin/hdfs" dfs -ls "${TEST_DIR}"

OUTPUT="$("${HADOOP_HOME}/bin/hdfs" dfs -cat "${TEST_DIR}/${TEST_FILE}")"
echo "File contents:"
echo "${OUTPUT}"

if [[ "${OUTPUT}" != "Hello Hadoop - Experiment 1" ]]; then
    die "HDFS uploaded the file, but the contents did not match the expected test output."
fi

green "HDFS file upload/read test passed."

# -----------------------------
# Final summary
# -----------------------------
echo
bold "============================================================"
green "HADOOP EXPERIMENT 1 SETUP SUCCESSFUL"
bold "============================================================"

echo
blue "Installation:"
echo "  Hadoop version : ${HADOOP_VERSION}"
echo "  Hadoop home    : ${HADOOP_HOME}"
echo "  Java home      : ${JAVA_HOME}"
echo "  HDFS test      : ${TEST_DIR}/${TEST_FILE}"

echo
blue "Useful commands:"
echo "  jps"
echo "  hdfs dfs -ls /"
echo "  hdfs dfs -ls ${TEST_DIR}"
echo "  hdfs dfs -cat ${TEST_DIR}/${TEST_FILE}"
echo "  start-dfs.sh"
echo "  start-yarn.sh"
echo "  stop-dfs.sh"
echo "  stop-yarn.sh"

echo
blue "Expected daemons:"
echo "  NameNode"
echo "  DataNode"
echo "  SecondaryNameNode"
echo "  ResourceManager"
echo "  NodeManager"

echo
yellow "For the practical:"
echo "  1. Install Java + SSH"
echo "  2. Install Hadoop"
echo "  3. Configure Hadoop XML files"
echo "  4. Format NameNode"
echo "  5. Start HDFS/YARN"
echo "  6. Verify with jps"
echo "  7. Test HDFS with mkdir/put/cat"

echo
green "Done. No hardcoded /home/<username> paths were used."
