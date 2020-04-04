import os
import sys

try:
    from requests import get
except ImportError:
    print("正在安装requests")
    res = os.system("pip3 install requests -i https:\/\/pypi.douban.com\/simple\/--trusted-host pypi.douban.com")
    if res != 0:
        print("requests安装失败")
        exit(0)

try:
    import paramiko
except ImportError:
    print("正在安装paramiko")
    res = os.system("pip3 install paramiko -i https:\/\/pypi.douban.com\/simple\/--trusted-host pypi.douban.com")
    if res != 0:
        print("paramiko安装失败")
        exit(0)
        
# 外部传入的参数集合
allArgvs = sys.argv[1:]
print(allArgvs)

# 服务器地址
serverHost = ''
# 服务器root登录密码
rootPassword = ''

argvIndex = 0
for argv in allArgvs:
    if argvIndex == 0:
        serverHost = argv
    elif argvIndex == 1:
        rootPassword = argv
    argvIndex = argvIndex + 1

if len(serverHost) == 0:
    print("服务器地址为空")
    exit(0)
if len(rootPassword) == 0:
    print("服务器root登录密码为空")
    exit(0)

print("输入参数: " + serverHost + ", " + rootPassword)

# 创建SSHClient
ssh=paramiko.SSHClient()

#允许不使用公钥访问
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

# 连接服务器，传入地址，端口，用户名和密码
ssh.connect(serverHost, 22, 'root', rootPassword)

# 获取IP
ip = get('https://api.ipify.org').text
print("当前IP为: " + ip)

# 获取服务器当前防火墙状态
cmd = 'sudo ufw status'
stdin,stdout,stderr = ssh.exec_command(cmd)
outError = bytes.decode(stderr.read())

if outError:
    print("检查防火墙状态失败: " + outError)
else:
    outStatus = bytes.decode(stdout.read())
    print("当前防火墙状态: " + outStatus)
    # 检查当前防火墙是否已允许该IP访问
    if outStatus.find(ip) == -1:
        print("该IP不在白名单中，配置该IP为允许访问")
        allowCMD = 'sudo ufw allow from ' + ip
        ssh.exec_command(allowCMD)
    else:
        print("该IP已在白名单中")

ssh.close()
