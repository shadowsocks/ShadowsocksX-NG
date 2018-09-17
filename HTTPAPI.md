# Features

* Check current status (on/off)

- Toggle the client
- Get server list
- Get current server
- Select server
- Add new / modify existing server
- Delete server
- Get current mode
- Switch mode

# Specification

URL: http://localhost:9528/

- #### Check current status (on/off)  `GET /status`

###### Sample Return

```
{
    "enable": true
}
```

- #### Toggle the client  `POST /status`

###### Sample Return

```
{
    "status": 1
}
```

`1` for success, `0` for failure.

- #### Get server list  `GET /server/list`

###### Sample Return

```
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

###### Sample Return

```
{
  "Id" : "93C127E0-49C9-4332-9CAD-EE6B9A3D1A8F"
}
```

- #### Select server  `POST /server/current`

###### Argument

| Name | Description                       | Sample                                 |
| ---- | --------------------------------- | -------------------------------------- |
| Id   | As returned in `GET /server/list` | "71552DCD-B298-4591-B59A-82DA4B07AEF8" |

###### Sample Return

```
{
    "status": 1
}
```

If the `Id` is invalid or fail to match any id in config, `"status": 0`. 

- #### Add Server / Modify Existing Server  `POST /server `

###### Argument

| Name          | Sample                 |
| ------------- | ---------------------- |
| ServerPort    | 49234                  |
| ServerHost    | jp1-sta40.somehost.com |
| Remark        | jp1                    |
| PluginOptions |                        |
| Plugin        |                        |
| Password      | Password               |
| Method        | chacha20-ietf-poly1305 |

To indicate modification, pass `Id`  in addition.

| Name | Description                       | Sample                                 |
| ---- | --------------------------------- | -------------------------------------- |
| Id   | As returned in `GET /server/list` | "71552DCD-B298-4591-B59A-82DA4B07AEF8" |

For meaning of the arguments, refer to `GET /server/list` and the Server Perferences Panel of the app.

###### Sample Return

```
{
    "status": 1
}
```

- #### Delete Server  `DELETE /server`

###### Argument

| Name | Description                       | Sample                                 |
| ---- | --------------------------------- | -------------------------------------- |
| Id   | As returned in `GET /server/list` | "71552DCD-B298-4591-B59A-82DA4B07AEF8" |

###### Sample Return

```
{
    "status": 1
}
```

If `Id` == id of current server, operation will no effect, `"status":0`.

If `Id` not match, `"status":0`.

- #### Get current mode  `GET /mode`

###### Sample Return

```
{
    "mode": "auto"
}
```

 `mode`∈ {"auto", "global", "manual"}.

- #### Switch mode  `POST /mode`

###### Argument

| Name | Description                | Sample   |
| ---- | -------------------------- | -------- |
| mode | As returned in `GET /mode` | "global" |

###### Sample Return

```
{
    "status": 1
    // 1 for succeed, 0 for fail  
}
```

---

All json names are case sensitive. Be careful.

