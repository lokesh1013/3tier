#!/bin/bash
ID=$(id -u)
LOG=/tmp/stack.log
R="\e[31m"
G="\e[32m"
Y="\e[33m"
B="\e[34m"
N="\e[0m"
STUDENT_WAR=https://github.com/devops2k18/DevOpsDecember/raw/master/APPSTACK/student.war

TOMCAT_HTTP_URL=http://mirrors.estointernet.in/apache/tomcat/tomcat-9/v9.0.24/bin/apache-tomcat-9.0.24.tar.gz
TOMCAT_TAR_FILE=$(echo $TOMCAT_HTTP_URL | awk -F / '{print $NF}')
TOMCAT_DIR_HOME=$(echo $TOMCAT_TAR_FILE | sed -e 's/.tar.gz//g')

CONN_HTTP_URL=http://mirrors.estointernet.in/apache/tomcat/tomcat-connectors/jk/tomcat-connectors-1.2.46-src.tar.gz
CONN_TAR_FILE=$(echo $CONN_HTTP_URL | awk -F / '{print $NF}')
CONN_DIR_HOME=$(echo $CONN_TAR_FILE | sed -e 's/.tar.gz//g')

MYSQL_JAR_URL=https://github.com/devops2k18/DevOpsDecember/raw/master/APPSTACK/mysql-connector-java-5.1.40.jar
MYSQL_JAR=$(echo $MYSQL_JAR_URL | awk -F / '{print $NF}')

if [ $ID -ne 0 ]; then
	echo " u should be a root user to perform this"
	exit 1
fi

VALIDATE(){
if [ $1 -eq 0 ]; then
	echo -e "$2  .....$G SUCCESS $N"
else 
	echo -e "$2  .....$R FAILURE $N"
	exit 12
fi
}

SKIP(){
	echo -e "$1 Exist... $Y SKIPPING $N"
}

###Data base server ####

yum install mariadb mariadb-server -y &>>$LOG
VALIDATE $? "mariadb installation"

systemctl enable mariadb &>>$LOG
systemctl restart mariadb &>>$LOG
echo "create database if not exists studentapp;
use studentapp;
CREATE TABLE if not exists Students(student_id INT NOT NULL AUTO_INCREMENT,
	student_name VARCHAR(100) NOT NULL,
    student_addr VARCHAR(100) NOT NULL,
	student_age VARCHAR(3) NOT NULL,
	student_qual VARCHAR(20) NOT NULL,
	student_percent VARCHAR(10) NOT NULL,
	student_year_passed VARCHAR(10) NOT NULL,
	PRIMARY KEY (student_id)
);
grant all privileges on studentapp.* to 'student'@'localhost' identified by 'student@1';" > /tmp/student.sql
mysql < /tmp/student.sql
VALIDATE $? "creating database"

####tomcat server ####

cd /opt 

if [ -f $TOMCAT_TAR_FILE ]; then
	SKIP "TOMCAT"
else
	wget $TOMCAT_HTTP_URL &>>$LOG
	VALIDATE $? "Downloading Tomcat"
fi

if [ -d $TOMCAT_DIR_HOME ]; then
	SKIP "TOMCAT dir"
else
	tar -xf $TOMCAT_TAR_FILE
	VALIDATE $? "extracting tomcat"
fi

cd $TOMCAT_DIR_HOME/webapps
rm -rf *;

wget $STUDENT_WAR &>>$LOG
VALIDATE $? "downloading student project"

cd ../lib

if [ -f $MYSQL_JAR ]; then
	SKIP "sql jar file"
else 
	wget $MYSQL_JAR_URL &>>$LOG
	VALIDATE $? "downloading sql jar file"
fi

cd ../conf
sed -i -e '/TestDB/ d' context.xml
VALIDATE $? "deleting the sql connector jar file if any present"
sed -i -e '$ i <Resource name="jdbc/TestDB" auth="Container" type="javax.sql.DataSource" maxTotal="100" maxIdle="30" maxWaitMillis="10000" username="student" password="student@1" driverClassName="com.mysql.jdbc.Driver" url="jdbc:mysql://localhost:3306/studentapp"/>' context.xml
VALIDATE $? "configuring context.xml"




#####web server with tomcat connector#######



yum install httpd -y &>>$LOG
systemctl restart httpd &>>$LOG
VALIDATE $? "webserver installation"
yum install httpd-devel java gcc -y &>>$LOG
VALIDATE $? "Installing GCC and httpd-devel and java"
cd /opt
if [ -f $CONN_TAR_FILE ]; then 
	SKIP "MOD_JK "
else
	wget $CONN_HTTP_URL &>>$LOG
	VALIDATE $? "downloading tomcatconnector"
fi
if [ -d $CONN_DIR_HOME ]; then
	SKIP "MOD_jk"
else 
	tar -xf $CONN_TAR_FILE
	VALIDATE $? "extracting MOD_JK file"
fi
if [ -f /etc/htttpd/modues/mod_jk.so ]; then
	SKIP "compiling mod_jk"
else
	cd $CONN_DIR_HOME/native
	sh configure --with-apxs=/bin/apxs &>>$LOG && make clean  &>>$LOG && make &>>$LOG && make install &>>$LOG
	VALIDATE $? "Compiling MOD_JK"
fi
cd /etc/httpd/conf.d
echo 'LoadModule jk_module modules/mod_jk.so
JkWorkersFile conf.d/workers.properties
JkLogFile logs/mod_jk.log
JkLogLevel info
JkLogStampFormat "[%a %b %d %H:%M:%S %Y]"
JkOptions +ForwardKeySize +ForwardURICompat -ForwardDirectories
JkRequestLogFormat "%w %V %T"
JkMount /student tomcatA
JkMount /student/* tomcatA' > mod_jk.conf

VALIDATE $? "creating mod_jk.conf"
echo '### Define workers
worker.list=tomcatA
### Set properties
worker.tomcatA.type=ajp13
worker.tomcatA.host=localhost
worker.tomcatA.port=8009' > workers.properties

VALIDATE $? "Creating workers.properties"

cd /opt/$TOMCAT_DIR_HOME/bin
sh shutdown.sh &>>$LOG
sh startup.sh &>>$LOG
VALIDATE $? "RESTARTING TOMCAT" 