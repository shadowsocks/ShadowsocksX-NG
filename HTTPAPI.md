# Features

* Check current status (on/off)

- Toggle the client

- Get server list

- Switch server

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

- #### Toggle the client  `POST /toggle`

###### Sample Return

```
{
    "status": 1
    // 1 for toggle succeed, 0 for fail  
}
```

- #### Get server list  `GET /servers`

###### Sample Return

```
[
	{
		"active": 1,
   		"id": "93C547E0-49C9-1234-9CAD-EE8D5C4A1A8F",
    	"remark": "us1",
		// remark: as in Server Preferences Panel of the app.
	},
	{
    	"active" : 0,
    	"id" : "71552DCD-B298-495E-904E-82DA4B07AEF8",
    	"remark" : "hk2"
  	},
  	{
    	"active" : 0,
    	"id" : "E8879F3D-95AE-4714-BC04-9B271C2BC52D",
    	"remark" : "jp1"
  	},...
]
```

- #### Switch server  `POST /servers`

###### Argument

| Name | Description                   | Sample                                 |
| ---- | ----------------------------- | -------------------------------------- |
| id   | As returned in `GET /servers` | "E8879F3D-95AE-4714-BC04-9B271C2BC52D" |

###### Sample Return

```
{
    "status": 1
    // 1 for succeed, 0 for fail
}
```

If the `id` is invalid or fail to match any `id` in config, "status" = 0. 

- #### Get current mode  `GET /mode`

###### Sample Return

```
{
    "mode": "auto"
}
```

 `mode`∈ {"auto", "global", "manual"}.

- #### Switch mode  `POST /mode`

###### Sample Return

```
{
    "status": 1
    // 1 for succeed, 0 for fail  
}
```

If the `mode`∉ {"auto", "global", "manual"}, "status" = 0. 