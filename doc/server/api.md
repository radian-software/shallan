# Shallan server API

## All endpoints

Failure due to wrong content type:

```
HTTP/1.1 415 UNSUPPORTED MEDIA TYPE
Content-Type: application/json
{
  error: "Expected application/json, got text/plain"
}
```

Failure due to malformed request body:

```
HTTP/1.1 400 BAD REQUEST
Content-Type: application/json
{
  error: "JSON parse error: Expecting value: line 1 column 1 (char 0)"
}
```

Failure due to wrong request parameters:

```
HTTP/1.1 422 UNPROCESSABLE ENTITY
Content-Type: application/json
{
  error: "Field 'txns' must be an array, was missing"
}
```

Failure due to unexpected error:

```
HTTP/1.1 500 INTERNAL SERVER ERROR
Content-Type: application/json
{
  error: "panic: runtime error: invalid memory address or nil pointer dereference"
}
```

## Download the latest SQLite database

```
% http GET :4381/api/v1/db
```

Success:

```
HTTP/1.1 200 OK
Content-Type: application/vnd.sqlite3
...
```

## Post a query to the server's copy of the database

```
% yq e -j <<"EOF" | http PATCH :4381/api/v1/db | yq e -P
txns:
  - id: "ec9c4577b563660ff81043e088b135e5"
    txn: |
      UPDATE playlists SET song_index = song_index + 1 WHERE id = '4e96d731420fd0c90b3c63f287c5f09e'
    timestampMs: 1622413313227
  - id: "a0e29d9652394760af793ef4e79e49db"
    txn: |
      UPDATE playlists SET song_index = song_index + 1 WHERE id = '4e96d731420fd0c90b3c63f287c5f09e'
    timestampMs: 1622413617859
  - id: "8a484499ac56ab739b1f2765084300dd"
    txn: |
      UPDATE playlists SET song_index = song_index + 1 WHERE id = '4e96d731420fd0c90b3c63f287c5f09e'
    timestampMs: 1622413823841
EOF
```

Success:

```
HTTP/1.1 200 OK
Content-Type: application/json
---
error: null
txns:
  - id: "ec9c4577b563660ff81043e088b135e5"
    attempted: true
    succeeded: true
  - id: "a0e29d9652394760af793ef4e79e49db"
    attempted: true
    succeeded: true
  - id: "8a484499ac56ab739b1f2765084300dd"
    attempted: true
    succeeded: true
```

Failure due to malformed or conflicting query:

```
HTTP/1.1 422 UNPROCESSABLE ENTITY
Content-Type: application/json
---
error: null
txns:
  - id: "ec9c4577b563660ff81043e088b135e5"
    attempted: true
    succeeded: true
  - id: "a0e29d9652394760af793ef4e79e49db"
    attempted: true
    succeeded: false
    error: "Error: some error message from SQLite"
  - id: "8a484499ac56ab739b1f2765084300dd"
    attempted: false
```

## Overwrite the server's database

```
% http POST :4381/api/v1/db Content-Type:application/vnd.sqlite3 < ... | yq e -P
```

Success:

```
HTTP/1.1 200 OK
Content-Type: application/json
---
error: null
```

## Delete the server's database

```
% http DELETE :4381/api/v1/db | yq e -P
```

Success:

```
HTTP/1.1 200 OK
Content-Type: application/json
---
error: null
```
