# Copyright
Most code in HTTPUserProxy.swift comes from [yichengchen's fork](https://github.com/yichengchen/ShadowsocksX-R/blob/42b409beb85aee19a4852e09e7c3e4c2f73f49d3/ShadowsocksX-NG/ApiServer.swift), with slight modification to solve some incompatibility due to obsolete methods.

# API Feature
1. Check current status (on/off)
2. Toggle the client
3. Get server list
4. Switch server
5. Get current mode
6. Switch mode

# HTTP API
**Port:** 9528

**Default response**

| Name   | Type | Description               |
| :----- | :--- | :------------------------ |
| status | int  | 1 for success, 0 for fail |

---

### Check current status (on/off)

`GET /status`

**Response**

| Name   | Type    | Description |
| :----- | :------ | :---------- |
| enable | boolean |             |

### Toggle the client 
`POST /toggle`

**NO** Parameter

### Get server list
`GET /servers`

**Response**

An **Array** of the following object:

| Name   | Type   | Description                                              |
| :----- | :----- | :------------------------------------------------------- |
| id     | string | internal UUID of the server                              |
| remark | string | refer to Remarks in Servers Perferences Panel of the app |
| active | int    | 1 for active, 0 for inactive                             |

### Switch server
`POST /servers`

**Parameter**

| Name | Type   | Description                 |
| :--- | :----- | :-------------------------- |
| id   | string | internal UUID of the server |

### Get current mode
`GET /mode`

**Response**

| Name | Type   | Description        |
| :--- | :----- | :----------------- |
| mode | string | auto/manual/global |

### Set current mode
`POST /mode`

**Parameter**

| Name | Type   | Description        |
| :--- | :----- | :----------------- |
| mode | string | auto/manual/global |