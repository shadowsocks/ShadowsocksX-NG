# Features

* Check current status (on/off)

- Turn on/off or toggle the client
- Get server list
- Get current server
- Select server
- Add new / modify existing server
- Delete server
- Get current mode
- Switch mode

# Specification

baseURL: http://localhost:9528/

- #### Check current status (on/off)  `GET /status`

###### Sample Shell command

```shell
$ curl -X GET http://localhost:9528/status
```

###### Sample Return

```json
{"enable": true}
```

- #### Turn on/off or toggle the client  `POST /status`

###### Sample Shell command

```shell
$ curl -X POST http://localhost:9528/status
```

The command above will toggle the client.

Or you may want to specify the argument

```shell
$ curl -X POST -d 'enable=false' http://localhost:9528/status 
```

###### Sample Return

```json
{"status": 1}
```

**Note**: `1` for command succeed, `0` for fail.

- #### Get server list  `GET /server/list`

###### Sample Shell command

```shell
$ curl -X GET http://localhost:9528/server/list
```

###### Sample Return

```json
[
  {
    "Id" : "93C127E0-49C9-4332-9CAD-EE6B9A3D1A8F",
    "Method" : "chacha20-ietf-poly1305",
    "Password" : "password",
    "Plugin" : "",
    "PluginOptions" : "",
    "Remark" : "jp1",
    "ServerHost" : "jp1-sta40.somehost.com",
    "ServerPort" : 49234
  },
  {
    "Id" : "71552DCD-B298-4591-B59A-82DA4B07AEF8",
    "Method" : "chacha20-ietf-poly1305",
    "Password" : "password",
    "Plugin" : "",
    "PluginOptions" : "",
    "Remark" : "us1",
    "ServerHost" : "us1-sta40.somehost.com",
    "ServerPort" : 49234
  },...
]
```

- #### Get current server `GET /server/current`

###### Sample Shell command

```shell
$ curl -X GET http://localhost:9528/server/current
```

###### Sample Return

```json
{"Id" : "93C127E0-49C9-4332-9CAD-EE6B9A3D1A8F"}
```

- #### Select server  `POST /server/current`

###### Sample Shell command

```shell
$ curl -X POST -d 'Id=71552DCD-B298-4591-B59A-82DA4B07AEF8' http://localhost:9528/server/current
```

###### Sample Return

```json
{"status": 1}
```

If the `Id` is invalid or fail to match any id in config, `"status": 0`. 

- #### Add Server / Modify Existing Server  `POST /server `

Sample Shell command

```shell
$ curl -X POST -d \
'ServerPort=49234&ServerHost=tw1-sta40.somehost.com&Remark=someRemark&PluginOptions=&Plugin=&Password=myPassword&Method=chacha20-ietf-poly1305' http://localhost:9528/server
```

To indicate modification, pass `Id`  in addition.

```shell
$ curl -X POST -d \
'Id=71552DCD-B298-4591-B59A-82DA4B07AEF8&ServerPort=49234&ServerHost=tw1-sta40.somehost.com&Remark=someRemark&PluginOptions=&Plugin=&Password=myPassword&Method=chacha20-ietf-poly1305' http://localhost:9528/server
```

For meaning of the arguments, refer to `GET /server/list` and the Server Perferences Panel of the app.

###### Sample Return

```json
{"status": 1}
```

- #### Delete Server  `DELETE /server`

Sample Shell command

```shell
$ curl -X POST -d 'Id=71552DCD-B298-4591-B59A-82DA4B07AEF8' http://localhost:9528/server
```

Sample Return

```json
{"status": 1}
```

If `Id` == id of current server, operation will no effect, `"status":0`.

If `Id` not match, `"status":0`.

- #### Get current mode  `GET /mode`

###### Sample Shell command

```shell
$ curl -X GET http://localhost:9528/mode
```

###### Sample Return

```json
{"mode": "auto"}
```

 `mode`∈ {"auto", "global", "manual"}.

- #### Switch mode  `POST /mode`

###### Sample Shell command

```shell
$ curl -X POST -d 'mode=global' http://localhost:9528/status
```

###### Sample Return

```json
{"status": 1}
```
