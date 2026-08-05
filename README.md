# Apache Hadoop Installation Guide for WSL (Windows Subsystem for Linux)

This guide provides step-by-step instructions for installing and configuring **Apache Hadoop 3.3.6** in **pseudo-distributed mode** on WSL (Ubuntu).

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Step 1: Download and Extract Hadoop](#step-1-download-and-extract-hadoop)
3. [Step 2: Configure Environment Variables](#step-2-configure-environment-variables)
4. [Step 3: Configure Hadoop Configuration Files](#step-3-configure-hadoop-configuration-files)
5. [Step 4: Format the HDFS NameNode](#step-4-format-the-hdfs-namenode)
6. [Step 5: Start Hadoop Services](#step-5-start-hadoop-services)
7. [Step 6: Access Hadoop Web UIs](#step-6-access-hadoop-web-uis)
8. [Stopping Hadoop Services](#stopping-hadoop-services)

---

## Prerequisites

Before installing Hadoop, ensure your system is updated and has Java and SSH installed.

### 1. Update Package List

```bash
sudo apt update && sudo apt upgrade -y
```

### 2. Install Java

Java 8 or Java 11 is recommended for Hadoop.

```bash
sudo apt install openjdk-8-jdk -y
```

Verify the Java installation:

```bash
java -version
```

### 3. Install SSH and PDSH

SSH is required for Hadoop to manage its nodes.

```bash
sudo apt install ssh pdsh -y
```

### 4. Configure SSH Key-Based Authentication

Set up passwordless localhost access:

```bash
ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 0600 ~/.ssh/authorized_keys
```

Test the SSH connection:

```bash
ssh localhost
```

(Type `exit` to return.)

---

## Step 1: Download and Extract Hadoop

### 1. Download Hadoop

You can download Hadoop using the official mirror, or via the pre-packaged Google Drive link:

- **Google Drive Link:** [Download Hadoop Archive](https://drive.google.com/file/d/1mMOZTVs1detba5EY0ZSUmIPfiohSHA9N/view?usp=sharing)

- **Official Mirror (Alternative):**

```bash
wget https://downloads.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz
```

### 2. Extract and Move the Archive

Extract the downloaded archive:

```bash
tar -xzvf hadoop-3.3.6.tar.gz
```

Move the extracted folder to `/usr/local/hadoop`:

```bash
sudo mv hadoop-3.3.6 /usr/local/hadoop
```

Set ownership of the Hadoop directory to your current user:

```bash
sudo chown -R $USER:$USER /usr/local/hadoop
```

---

## Step 2: Configure Environment Variables

### 1. Edit Bash Configuration

Open your bash configuration file:

```bash
nano ~/.bashrc
```

### 2. Add Hadoop Environment Variables

**Add** (append — do not replace anything) the following lines to the end of the file:

```bash
export HADOOP_HOME=/usr/local/hadoop
export HADOOP_INSTALL=$HADOOP_HOME
export HADOOP_MAPRED_HOME=$HADOOP_HOME
export HADOOP_COMMON_HOME=$HADOOP_HOME
export HADOOP_HDFS_HOME=$HADOOP_HOME
export YARN_HOME=$HADOOP_HOME
export HADOOP_COMMON_LIB_NATIVE_DIR=$HADOOP_HOME/lib/native
export PATH=$PATH:$HADOOP_HOME/sbin:$HADOOP_HOME/bin
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
```

> **Note:** Adjust `JAVA_HOME` if you installed a different Java version. You can check the correct path with `update-alternatives --config java`.

Save and close the file (`Ctrl+O`, `Enter`, then `Ctrl+X`), and apply the changes:

```bash
source ~/.bashrc
```

---

## Step 3: Configure Hadoop Configuration Files

Navigate to the Hadoop configuration directory:

```bash
cd /usr/local/hadoop/etc/hadoop
```

### 1. Edit `hadoop-env.sh`

Open the file to set the Java path:

```bash
nano hadoop-env.sh
```

Find the existing (commented-out) line for `export JAVA_HOME` and **replace** it with:

```bash
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
```

### 2. Edit `core-site.xml`

Open the file:

```bash
nano core-site.xml
```

The file starts with empty `<configuration>\n</configuration>` tags. **Add** the following property inside them (this replaces the empty tags, not the whole file):

```xml
<configuration>
    <property>
        <name>fs.defaultFS</name>
        <value>hdfs://localhost:9000</value>
    </property>
</configuration>
```

### 3. Edit `hdfs-site.xml`

Open the file:

```bash
nano hdfs-site.xml
```

**Add** (replace the empty `<configuration>` tags with) the following configuration, which defines where NameNode and DataNode data will be stored:

```xml
<configuration>
    <property>
        <name>dfs.replication</name>
        <value>1</value>
    </property>
    <property>
        <name>dfs.namenode.name.dir</name>
        <value>/usr/local/hadoop/data/dfs/namenode</value>
    </property>
    <property>
        <name>dfs.datanode.data.dir</name>
        <value>/usr/local/hadoop/data/dfs/datanode</value>
    </property>
</configuration>
```

### 4. Edit `mapred-site.xml`

Open the file:

```bash
nano mapred-site.xml
```

**Add** (replace the empty `<configuration>` tags with) the following configuration:

```xml
<configuration>
    <property>
        <name>mapreduce.framework.name</name>
        <value>yarn</value>
    </property>
    <property>
        <name>mapreduce.application.classpath</name>
        <value>$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/*:$HADOOP_MAPRED_HOME/share/hadoop/mapreduce/lib/*</value>
    </property>
</configuration>
```

### 5. Edit `yarn-site.xml`

Open the file:

```bash
nano yarn-site.xml
```

**Add** (replace the empty `<configuration>` tags with) the following configuration:

```xml
<configuration>
    <property>
        <name>yarn.nodemanager.aux-services</name>
        <value>mapreduce_shuffle</value>
    </property>
    <property>
        <name>yarn.nodemanager.aux-services.mapreduce.shuffle.class</name>
        <value>org.apache.hadoop.mapred.ShuffleHandler</value>
    </property>
</configuration>
```

---

## Step 4: Format the HDFS NameNode

Before starting Hadoop for the first time, you must format the NameNode:

```bash
hdfs namenode -format
```

---

## Step 5: Start Hadoop Services

### 1. Start HDFS (NameNode and DataNode)

```bash
start-dfs.sh
```

### 2. Start YARN (ResourceManager and NodeManager)

```bash
start-yarn.sh
```

### 3. Verify Processes

Verify that all processes are running:

```bash
jps
```

You should see output similar to:

```
NameNode
DataNode
ResourceManager
NodeManager
SecondaryNameNode
Jps
```

---

## Step 6: Access Hadoop Web UIs

You can access the Hadoop dashboards directly from your Windows web browser:

- **HDFS NameNode UI:** [http://localhost:9870](http://localhost:9870)
- **YARN ResourceManager UI:** [http://localhost:8088](http://localhost:8088)

---

## Stopping Hadoop Services

When you are done, stop the services using:

```bash
stop-yarn.sh
stop-dfs.sh
```

---

## Quick Reference

| Task | Command |
|---|---|
| Start HDFS | `start-dfs.sh` |
| Start YARN | `start-yarn.sh` |
| Stop YARN | `stop-yarn.sh` |
| Stop HDFS | `stop-dfs.sh` |
| Check running processes | `jps` |
| Format NameNode (first-time only) | `hdfs namenode -format` |
| HDFS Web UI | http://localhost:9870 |
| YARN Web UI | http://localhost:8088 |
