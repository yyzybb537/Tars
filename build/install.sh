#!/bin/bash

set -e
set -x

PWD_DIR=`pwd`
MachineIp=127.0.0.1
MachineName=127.0.0.1
MysqlIncludePath=
MysqlLibPath=

INSTALL=apt

test -f mysql-5.6.26.tar.gz || wget https://downloads.mysql.com/archives/get/file/mysql-5.6.26.tar.gz
test -f apache-maven-3.3.9-bin.tar.gz || wget http://mirrors.hust.edu.cn/apache/maven/maven-3/3.3.9/binaries/apache-maven-3.3.9-bin.tar.gz
test -f jdk-8u171-linux-x64.tar.gz || wget http://download.oracle.com/otn-pub/java/jdk/8u171-b11/512cd62ec5174c3487ac17c61aaa89e8/jdk-8u171-linux-x64.tar.gz?AuthParam=1527412892_6c35732042741943afe9f01270d5bfc0 -O jdk-8u171-linux-x64.tar.gz
test -f resin-4.0.49.tar.gz || wget http://www.caucho.com/download/resin-4.0.49.tar.gz

##安装glibc-devel

#$INSTALL install -y glibc-devel

##安装flex、bison

$INSTALL install -y flex bison

##安装zlib
test -d zlib || git clone https://github.com/madler/zlib.git
cd zlib
rm build -rf
mkdir -p build
cd build
cmake ..
make
sudo make install
cd ${PWD_DIR}

##安装cmake

#tar zxvf cmake-2.8.8.tar.gz
#cd cmake-2.8.8
#./bootstrap
#make
#make install
#cd -

##安装java jdk
tar zxvf jdk-8u171-linux-x64.tar.gz
echo "export JAVA_HOME=${PWD_DIR}/jdk1.8.0_171" >> /etc/profile
echo "CLASSPATH=\$JAVA_HOME/lib/dt.jar:\$JAVA_HOME/lib/tools.jar" >> /etc/profile
echo "PATH=\$JAVA_HOME/bin:\$PATH" >> /etc/profile
echo "export PATH JAVA_HOME CLASSPATH" >> /etc/profile

source /etc/profile

java -version

##安装maven
tar zxvf apache-maven-3.3.9-bin.tar.gz
echo "export MAVEN_HOME=${PWD_DIR}/apache-maven-3.3.9/" >> /etc/profile
echo "export PATH=\$PATH:\$MAVEN_HOME/bin" >> /etc/profile

source /etc/profile

mvn -v

##安装resin

cp resin-4.0.49.tar.gz /usr/local/
cd /usr/local/
tar zxvf resin-4.0.49.tar.gz
cd resin-4.0.49
./configure --prefix=/usr/local/resin-4.0.49
make
make install
cd ${PWD_DIR}
rm /usr/local/resin -f
ln -s /usr/local/resin-4.0.49 /usr/local/resin

##安装rapidjson
$INSTALL install -y git

test -d rapidjson || git clone https://github.com/Tencent/rapidjson.git

cp -r ./rapidjson ../cpp/thirdparty/

## 安装mysql
systemctl daemon-reload
service mysql stop || echo -n
killall -9 mysqld || echo -n
$INSTALL install -y ncurses-devel || $INSTALL install -y libncurses5-dev
$INSTALL install -y zlib-devel || $INSTALL install -y zlibc

if [   ! -n "$MysqlIncludePath"  ] 
  then
	tar zxvf mysql-5.6.26.tar.gz
	cd mysql-5.6.26
	cmake . -DCMAKE_INSTALL_PREFIX=/usr/local/mysql-5.6.26 -DWITH_INNOBASE_STORAGE_ENGINE=1 -DMYSQL_USER=mysql -DDEFAULT_CHARSET=utf8 -DDEFAULT_COLLATION=utf8_general_ci
	make
	make install
    rm /usr/local/mysql -f
	ln -s /usr/local/mysql-5.6.26 /usr/local/mysql
	cd -
  else
  	## 根据mysql 库路径 配置 设置cpp/build/CMakeLists.txt
  	sed -i "s@/usr/local/mysql/include@${MysqlIncludePath}@g" ../cpp/build/CMakeLists.txt
  	sed -i "s@/usr/local/mysql/lib@${MysqlLibPath}@g" ../cpp/build/CMakeLists.txt

fi

$INSTALL install -y perl
cd /usr/local/mysql
useradd mysql || echo -n
rm -rf /usr/local/mysql/data
mkdir -p /data/mysql-data
rm /usr/local/mysql/data -f
ln -s /data/mysql-data /usr/local/mysql/data
chown -R mysql:mysql /data/mysql-data /usr/local/mysql/data
cp support-files/mysql.server /etc/init.d/mysql

#$INSTALL install -y perl-Module-Install.noarch
perl scripts/mysql_install_db --user=mysql
cd -

sed -i "s/192.168.2.131/${MachineIp}/g" `grep 192.168.2.131 -rl ./conf/*` || echo -n
cp ./conf/my.cnf /usr/local/mysql/

##启动mysql
initChkconfig()
{
    $INSTALL install sysv-rc-conf
    chmod 755 chkconfig
    cp chkconfig /usr/bin
}

systemctl enable mysql.service
systemctl daemon-reload
service mysql start
#which chkconfig || initChkconfig
#chkconfig mysql on

##添加mysql的bin路径
echo "PATH=\$PATH:/usr/local/mysql/bin" >> /etc/profile
echo "export PATH" >> /etc/profile
source /etc/profile

##修改mysql root密码
cd /usr/local/mysql/
./bin/mysqladmin -uroot -proot password 'root@appinside' || ./bin/mysqladmin -uroot -proot@appinside password 'root@appinside'
./bin/mysqladmin -uroot -proot -h ${MachineName} password 'root@appinside' || ./bin/mysqladmin -uroot -proot@appinside -h ${MachineName} password 'root@appinside'
cd -

##添加mysql的库路径
echo "/usr/local/mysql/lib/" >> /etc/ld.so.conf
ldconfig


##安装java语言框架
cd ../java/
mvn clean install 
mvn clean install -f core/client.pom.xml 
mvn clean install -f core/server.pom.xml
cd -

##安装c++语言框架
cd ../cpp/build/
chmod u+x build.sh
./build.sh all
./build.sh install
cd -

##Tars数据库环境初始化
mysql -uroot -proot@appinside -e "grant all on *.* to 'tars'@'%' identified by 'tars2015' with grant option;"
mysql -uroot -proot@appinside -e "grant all on *.* to 'tars'@'localhost' identified by 'tars2015' with grant option;"
mysql -uroot -proot@appinside -e "grant all on *.* to 'tars'@'${MachineName}' identified by 'tars2015' with grant option;"
mysql -uroot -proot@appinside -e "flush privileges;"

cd ../cpp/framework/sql/
sed -i "s/192.168.2.131/${MachineIp}/g" `grep 192.168.2.131 -rl ./*` || echo -n
sed -i "s/db.tars.com/${MachineIp}/g" `grep db.tars.com -rl ./*` || echo -n
chmod u+x exec-sql.sh
./exec-sql.sh
cd -

##打包框架基础服务
cd ../cpp/build/
make framework-tar

make tarsstat-tar
make tarsnotify-tar
make tarsproperty-tar
make tarslog-tar
make tarsquerystat-tar
make tarsqueryproperty-tar
cd -

##安装核心基础服务
mkdir -p /usr/local/app/tars/
cd ../cpp/build/
cp framework.tgz /usr/local/app/tars/
cd /usr/local/app/tars
tar xzfv framework.tgz

sed -i "s/192.168.2.131/${MachineIp}/g" `grep 192.168.2.131 -rl ./*` || echo -n
sed -i "s/db.tars.com/${MachineIp}/g" `grep db.tars.com -rl ./*` || echo -n
sed -i "s/registry.tars.com/${MachineIp}/g" `grep registry.tars.com -rl ./*` || echo -n
sed -i "s/web.tars.com/${MachineIp}/g" `grep web.tars.com -rl ./*`

chmod u+x tars_install.sh
./tars_install.sh

./tarspatch/util/init.sh

##安装web管理系统
cd ${PWD_DIR}
cd ../web/
sed -i "s/db.tars.com/${MachineIp}/g" `grep db.tars.com -rl ./src/main/resources/*` || echo -n
sed -i "s/registry1.tars.com/${MachineIp}/g" `grep registry1.tars.com -rl ./src/main/resources/*` || echo -n
sed -i "s/registry2.tars.com/${MachineIp}/g" `grep registry2.tars.com -rl ./src/main/resources/*` || echo -n

mvn clean package
cp ./target/tars.war /usr/local/resin/webapps/

cd -

mkdir -p /data/log/tars/
cp ./conf/resin.xml /usr/local/resin/conf/

/usr/local/resin/bin/resin.sh start
