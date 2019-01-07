# 代码下载与依赖工具编译

    $ mkdir -p $GOPATH/src/energy.com

    $ cd $GOPATH/src/energy.com/

    $ git clone http://192.168.1.232/blockchain/install-fabric.git
    
    如果是第一次使用，或者fabric网络镜像的大版本更新了，则需要用fabric源代码编译出依赖的工具，否则可跳过下面的命令。
    
    $ mkdir -p $GOPATH/src/github.com/hyperledger

    $ cd $GOPATH/src/github.com/hyperledger

    $ git clone http://192.168.1.232/blockchain/fabric.git

    $ cd $GOPATH/src/github.com/hyperledger/fabric

    $ make configtxgen && make cryptogen

    $ cp build/bin/c*gen $GOPATH/src/energy.com/install-fabric/source/tools/$(go env GOOS)-$(go env GOARCH)/

# 运行脚本启动区块链网络

    $ cd $GOPATH/src/energy.com/install-fabric

    $ sudo make [up|down]
    
`相关配置文件:`

    节点和安装的只能合约的配置文件:
        $GOPATH/src/energy.com/install-fabric/source/.env
    
    如果是用来做性能测试，可以安装 http://192.168.1.232/blockchain/chaincode.git 库master分之的performance合约做测试，结合压测工具JMeter做开发内部的性能测试。

