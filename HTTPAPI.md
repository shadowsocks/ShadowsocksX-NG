# Features

* Check current status (on/off)

- Turn on/off or toggle the client
- Get server list
- Get current server
- Activate server
- Add new server
- Modify server
- Delete server
- Get current mode
- Switch mode

# Specification

**PORT:** 9528

### HTTP Status Code

- 200 - Succeed
- 400 - Fail
- 404 (For `PATCH /servers/{ID}` and `DELETE /servers/{ID}`) - `{ID}` Not found 
- 404 (For `GET /current`) No server is activated

### Methods

Note: To run the sample shell commands, replace the `Id` (if any) below for your own ones.

- #### Check current status (on/off)  `GET /status`

###### Sample Shell command

```shell
$ curl -X GET http://localhost:9528/status
```

###### Sample Return

```json
{"Enable": true}
```

- #### Turn on/off or toggle the client  `PUT /status`

###### Sample Shell command

```shell
curl -X PUT http://localhost:9528/status -d 'Enable=false'
```

Omit the argument `Enable` to **toggle**.

- #### Get server list  `GET /servers`

###### Sample Shell command

```shell
$ curl -X GET http://localhost:9528/servers
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

- #### Get current server `GET /current`

###### Sample Shell command

```shell
$ curl -X GET http://localhost:9528/current
```

###### Sample Return

```json
{
    "Id" : "93C127E0-49C9-4332-9CAD-EE6B9A3D1A8F",
    "Method" : "chacha20-ietf-poly1305",
    "Password" : "password",
    "Plugin" : "",
    "PluginOptions" : "",
    "Remark" : "jp1",
    "ServerHost" : "jp1-sta40.somehost.com",
    "ServerPort" : 49234
  }
```

- #### Activate server  `PUT /current`

###### Sample Shell command

```shell
$ curl -X PUT http://localhost:9528/current -d 'Id=71552DCD-B298-4591-B59A-82DA4B07AEF8'
```

- #### Add Server  `POST /servers `

###### Sample Shell command

```shell
$ curl -X POST http://localhost:9528/servers -d 'ServerPort=6666&ServerHost=tw1-sta40.somehost.com&Remark=someRemark&PluginOptions=&Plugin=&Password=myPassword&Method=chacha20-ietf-poly1305'
```

- #### Modify Server  `PATCH /servers/{ID} `

###### Sample Shell command

```shell
$ curl -X PATCH http://localhost:9528/servers/71552DCD-B298-4591-B59A-82DA4B07AEF8 -d 'ServerPort=6666&Remark=someRemark'
```

- #### Delete Server  `DELETE /server/{ID}`

###### Sample Shell command

```shell
$ curl -X DELETE http://localhost:9528/servers/71552DCD-B298-4591-B59A-82DA4B07AEF8
```

- #### Get current mode  `GET /mode`

###### Sample Shell command

```shell
$ curl -X GET http://localhost:9528/mode
```

###### Sample Return

```json
{"Mode": "auto"}
```

 `mode`∈ {"auto", "global", "manual"}.

- #### Switch mode  `PUT /mode`

###### Sample Shell command

```shell
$ curl -X PUT http://localhost:9528/status -d 'Mode=global'
```
