---
title: Docker+Vagrant 构建完全自动化的 CI/CD
date: 2020-12-03 11:18:34
tags: [docker, devops]
categories: docker
---

如果你的开发流程是下面👇这个样子的， 那么你一定很好奇， 为什么我提交到仓库的代码可以自动部署并访问到最新的提交内容  

![221380_01_devops完整流程](https://pic2.hanmaker.com/im/images/221380_01_devops%E5%AE%8C%E6%95%B4%E6%B5%81%E7%A8%8B.jpg)



这就是近年来兴起的 [DevOps](https://azure.microsoft.com/zh-cn/overview/what-is-devops/) 文化， 很方便的解决了开发人员和运维人员每次发布版本需要联调沟通等问题， 缩短了程序发布时间， 可以以更短的周期进行迭代。

所以在收集了很多教程之后， 我也搭建了一个可自动测试，测试用例通过后可自动部署的 CI/CD 流程

### 实验前准备

1. VirtualBox 用来模拟需要用到的服务器(大概4台，云服务器也可以)
2. Vagrant 用来编排 VirtualBox 里的虚拟机(一台一台服务器里面配置环境太累了)
3. 了解 Vagrant 和 Docker 的简单用法

### 初始化服务器环境

首先我们要用 VirtualBox 初始化4台centos 系统的Linux主机。  

| HostName   | IP Address    | 作用                                                         |
| ---------- | ------------- | ------------------------------------------------------------ |
| gitlab     | 192.168.33.10 | 安装gitlab服务，提供代码仓库等作用，类似github               |
| gitlab_dns | 192.168.33.13 | 给其他虚拟机提供统一的DNS查找服务， 不用每台虚拟机配置一份hosts文件 |
| gitlab_ci  | 192.168.33.11 | 安装 gitlab runner 提供 代码的持续集成服务                   |
| gitlab_cd  | 192.168.33.12 | 安装 gitlab runner 提供 代码的持续部署服务                   |

按照上面的表格， 我们设定了4台服务器名称， 也给每台服务器固定了内网地址， 这样我们每次重启系统就不用重新配置网络了。结合这份表格可以用 Vargentfile 启动4台服务器并安装好环境（每台系统我单独配置了一份shell脚本， 让环境直接初始化好）

```
# -*- mode: ruby -*-
# vi: set ft=ruby :
boxes = [
  {
    :name => "gitlab",
    :eth1 => "192.168.33.10",
    :mem => "4096",
    :cpu => "2",
    :folder => "./gitlab",
    :shell => "./gitlab/bootstrap.sh"				# 这份shell 是安装 gitlab 服务并自启
  },
  {
    :name => "gitlab_dns",
    :eth1 => "192.168.33.13",
    :mem => "1024",
    :cpu => "1",
    :folder => "./gitlab_dns",
    :shell => "./gitlab_dns/bootstrap.sh"   # 这份shell 是安装 docker 并 通过docker 启动一个dns服务
  },
  {
    :name => "gitlab_ci",
    :eth1 => "192.168.33.11",
    :mem => "2048",
    :cpu => "2",
    :folder => "./gitlab_ci",
    :shell => "./gitlab_ci/bootstrap.sh"   # 这份shell 是安装 docker 和 gitlab runner 组件
  },
  {
    :name => "gitlab_cd",
    :eth1 => "192.168.33.12",
    :mem => "2048",
    :cpu => "2",
    :folder => "./gitlab_ci",
    :shell => "./gitlab_ci/bootstrap.sh"  # 这份shell和ci是同一个脚本
  },
]

Vagrant.configure("2") do |config|
  config.vm.box = "centos/7"
  boxes.each do |opts|
      config.vm.define opts[:name] do |config|
        config.vm.provider "virtualbox" do |v|
          v.customize ["modifyvm", :id, "--memory", opts[:mem]]
          v.customize ["modifyvm", :id, "--cpus", opts[:cpu]]
        end

        config.vm.network :private_network, ip: opts[:eth1]
        config.vm.synced_folder opts[:folder], "/mnt", type: "nfs"
        config.vm.provision "shell", path: opts[:shell]
      end
  end
end
```

如果顺利初始化成功后， 你将有4台服务器， 分别是

1. 已经安装好 gitlab 的服务器，提供代码的仓库
2. 通过 docker 对外提供dns服务的 gitlab_dns 服务器
3. 安装好 gitlab runner 和 docker 的 ci 服务器
4. 安装好 gitlab runner 和 docker 的 cd 服务器

以上 Vargentfile 和 shell 文件可以到[我的 github](https://github.com/ycjiafei/gitlab-cicd) 仓库上复制

### 设置 gitlab

`vagrant up`  启动成功上述4台虚拟机后，然后配置一下宿主机的 dns ，用来通过域名方式 `http://gitlab.example.com/` 访问 gitlab 页面， 不配置也可以通过直接访问 ip 地址 `192.168.33.10` 的形式查看 gitlab

![image-20201207121956980](https://pic2.hanmaker.com/im/images/image-20201207121956980.png) 

![](https://pic2.hanmaker.com/im/images/20201207121718.png)

第一次启动需要设置密码， 然后可以通过 默认用户名root 和设置的密码登陆 gitlab, 登陆成功后需要像使用 github 一样添加宿主机的公钥到网站上， 放便后面我们对代码的 pull 和 push

![image-20201207122419995](https://pic2.hanmaker.com/im/images/image-20201207122419995.png)

### 添加一个项目

能顺利进入 gitlab 了， 那么顺利成章的需要测试一下我们是否能够初始化项目并且成功pull 和 push 操作， 这里有一份 [go 代码](https://github.com/ycjiafei/gitlab-cicd/tree/main/code)， 来当作这次ci cd 实验的准备

```go
# main.go
func main() {
	http.HandleFunc("/", httpFunc.SayHello)           //设置访问的路由
	err := http.ListenAndServe(":9090", nil) //设置监听的端口
	if err != nil {
		log.Fatal("ListenAndServe: ", err)
	}
}

# httpFunc/helloHandler.go
func SayHello(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "Hello World!") //这个写入到w的是输出到客户端的
}

# test/main_test.go
func TestHelloWorld(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/", httpFunc.SayHello)

	r, _ := http.NewRequest(http.MethodGet, "/", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, r)
	resp := w.Result()
	if resp.StatusCode != http.StatusOK {
		t.Errorf("Response code is %v", resp.StatusCode)
	}
	body, _ := ioutil.ReadAll(resp.Body)
	defer resp.Body.Close()
	if string(body) != "Hello World!" {
		t.Errorf("Response Body is %s", string(body))
	}
}
```

本地执行单元测试检验下我们的代码是否有问题

```shell
go test .
ok      code/test       0.109s
```

So, 我们可以在 gitlab 上新建一个仓库 gohttp 来上传了

![image-20201207135149685](https://pic2.hanmaker.com/im/images/image-20201207135149685.png)



### gitlab runner 设置

首先进入我们的 gitlab ci 服务器 `vagrant ssh gitlab_ci `配置 dns

```shell
sudo vim /etc/resolv.conf
nameserver 192.168.33.13  # 添加这一行
然后ping一下域名是否能成功
ping gitlab.example.com
```

dns 配置好之后可以设置 gitlab runner 了

进入 gitlab.example.com, 查看 runner 的 token

![image-20201207140539173](https://pic2.hanmaker.com/im/images/image-20201207140539173.png)

![image-20201207140551357](https://pic2.hanmaker.com/im/images/image-20201207140551357.png)

进入 gitlab_ci 虚拟机

```shell
[vagrant@localhost ~]$ sudo gitlab-ci-multi-runner register
Runtime platform                                    arch=amd64 os=linux pid=3016 revision=8fa89735 version=13.6.0
Running in system-mode.

Enter the GitLab instance URL (for example, https://gitlab.com/):
http://gitlab.example.com/       # gitlab 域名
Enter the registration token:
dPLFPqnA1dw2vzkAaENG					   # gitlab 项目的 token
Enter a description for the runner:
[localhost.localdomain]:
Enter tags for the runner (comma-separated):
golang-test                             # runner 的 tag
Registering runner... succeeded                     runner=dPLFPqnA
Enter an executor: kubernetes, shell, ssh, virtualbox, docker+machine, docker-ssh+machine, custom, docker, docker-ssh, parallels:
docker														# runner 的 环境 
Runner registered successfully. Feel free to start it, but if it's running already the config should be automatically reloaded!
```

然后刷新gitlab 页面， 可以看到 runner 已经注册成功了

![image-20201207140956021](https://pic2.hanmaker.com/im/images/image-20201207140956021.png)

同样的步骤可以在 gitlab_cd 服务器上执行一遍， 不过这次我们的 runner 环境要选择shell，

至此， 我们有了一个 tag 为 golang-test 的 runner 来执行 我们 go 项目的 ci （自动测试用）， tag 为 docker-deploy 的项目进行 cd （自动部署用）

![image-20201207141045461](https://pic2.hanmaker.com/im/images/image-20201207141045461.png)

在项目下新增 dockerfile 用来在docker 中运行我们的项目

```dockerfile
FROM golang AS build-env
ADD . /app
WORKDIR /app
RUN GOOS=linux GOARCH=386 go build -o gohttp main.go

FROM alpine
COPY --from=build-env /app/gohttp /usr/local/bin/gohttp
EXPOSE 9090
CMD [ "gohttp" ]
```

新增 .gitlab-ci.yml 让 gitlab runner 运行

```yaml
stages:
  - test
  - deploy

test-job:
  stage: test
  tags:
    - golang-test
  script:
    - go test ./test

deploy-job:
  stage: deploy
  tags:
    - docker-deploy
  script:
    - docker build -t gohttp .
    - if [ $(docker ps -aq --filter name=helloworld) ]; then docker rm -f helloworld;fi
    - docker run -d -p 9090:9090 --name helloworld gohttp
```

然后将改动 push 到 master 分支， 然后进入 CICD 看板， 可以看到已经在帮我们做ci和cd了

![image-20201207141731401](https://pic2.hanmaker.com/im/images/image-20201207141731401.png)

![image-20201207141530798](https://pic2.hanmaker.com/im/images/image-20201207141530798.png)



![image-20201207141545906](https://pic2.hanmaker.com/im/images/image-20201207141545906.png)

![image-20201207141600948](https://pic2.hanmaker.com/im/images/image-20201207141600948.png)

测试通过后会自动部署， 部署成功后可以访问 gitlab_cd 服务器的 ip 和应用程序的端口形式看到部署的应用， 同时也可以在 gitlab dns 服务器上为 cd 服务器添加一个 host 域名， 这样可以直接用域名访问程序

![image-20201207141855667](https://pic2.hanmaker.com/im/images/image-20201207141855667.png)

至此， cicd 已经搭建完成， 我在本地经过多次 修改代码 然后 git push 到 gitlab 上， 程序都能相应的执行和部署到 cd服务器的 9090 端口， 大功告成！