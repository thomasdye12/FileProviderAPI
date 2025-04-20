<?php

$GLOBALS["FileProviderFileURL"] =  "/Volumes/filesrv04/TDSCloud";
function FileProvider_Files_Root($user) {
    return  FileProvider_Files(null, $user);
}

function FileProvider_Files($parentId,$user) {
    
    global $FileProviderFiles;
    $parent = isset($body['parentId']) ? decodeId($body['parentId']) : null;
    $GUUID = $user["GeneratedUID"];
    //  find all items in the db where the parentId is  == $parentId, and the GUUID is == $GUUID
    $items = $FileProviderFiles->find(["parentId" => $parentId, "GUUID" => $GUUID]);
    // convert the items to an array
    $items = iterator_to_array($items);
    // check if null and return null
    if ($items == null) {
        return [];
    }
    return $items;

}



// helper: decode a base64 URL‑safe ID
function decodeId(string $encoded): string {
    return base64_decode(strtr($encoded, '-_', '+/'));
}

// helper: ensure user owns the item (or abort)
function requireOwnership(array $item, array $user) {
    if ($item['GUUID'] !== $user['GeneratedUID']) {
        http_response_code(403);
        echo json_encode(['error'=>'Forbidden']);
        exit;
    }
}

// ensure the uploads root exists, return it
function uploadRoot(): string {
    $root = rtrim($GLOBALS["FileProviderFileURL"], DIRECTORY_SEPARATOR);
    if (!is_dir($root)) {
        mkdir($root, 0755, true);
    }
    return $root;
}
// prefix a stored (relative) path with the global root
function fullPath(string $relativePath): string {
    return uploadRoot() . DIRECTORY_SEPARATOR . ltrim($relativePath, DIRECTORY_SEPARATOR);
}



// GET    /FileProvider/items              → list root
// GET    /FileProvider/items/{id}         → get metadata
// GET    /FileProvider/items/{id}/content → download
// POST   /FileProvider/items              → create
// PUT    /FileProvider/items/{id}         → rename/move
// DELETE /FileProvider/items/{id}         → delete
// PUT    /FileProvider/items/{id}/content → upload new content

function FileProvider_GetItem($encodedId, $user) {
    global $FileProviderFiles;

    // 1) decode the ID
    $id = decodeId($encodedId);

    // 2) if this is the Trash container, return a synthetic folder
    if ($id === "NSFileProviderTrashContainerItemIdentifier") {
        // you can choose your fields here—just enough so the client
        // sees a folder named “Recently Deleted”
        return [
            'id'              => $id,
            // show it as a child of the root container
            'parentId'        => null,
            'GUUID'           => $user['GeneratedUID'],
            'name'            => $id,
            'type'            => 'folder',
            // no content versioning needed for a virtual folder
            'contentVersion'  => '',
            'metadataVersion' => '',
            'createdAt'       => time(),
            'updatedAt'       => time(),
            'Trash'          => true,
        ];
    } else if ($id === "NSFileProviderRootContainerItemIdentifier") {
        // 2) if this is the root container, return a synthetic folder
        return [
            'id'              => $id,
            'parentId'        => null,
            'GUUID'           => $user['GeneratedUID'],
            'name'            => $id,
            'type'            => 'folder',
            // no content versioning needed for a virtual folder
            'contentVersion'  => '',
            'metadataVersion' => '',
            'createdAt'       => time(),
            'updatedAt'       => time(),
            'ROOT'          => true,
        ];
    }

    // 3) otherwise fall back to your normal lookup
    $item = $FileProviderFiles->findOne([
        'id'   => $id,
        'GUUID'=> $user['GeneratedUID']
    ]);

    if (!$item) {
        http_response_code(404);
        return ['error'=>'Not found'];
    }



    return FileProvider_FileStruct($item);
}

// FileProvider_GetItems
function FileProvider_GetItems($encodedId, $user) {
    global $FileProviderFiles;
    $id = decodeId($encodedId);
    $items = $FileProviderFiles->find(['parentId'=>$id, 'GUUID'=>$user['GeneratedUID']]);
    if (!$items) {
        http_response_code(404);
        // echo json_encode(['error'=>'Not found']);
        return ['error'=>'Not found'];
    }
    $items = iterator_to_array($items);
     if ($items == null) {
        return [];
     }
     // for each item in the array, run the FileProvider_FileStruct function
    foreach ($items as $key => $item) {
        $items[$key] = FileProvider_FileStruct($item);
    }
    return $items;
}

function FileProvider_GetContent($encodedId, $user) {
    global $FileProviderFiles;
    $id   = decodeId($encodedId);
    $item = $FileProviderFiles->findOne(['id'=>$id, 'GUUID'=>$user['GeneratedUID']]);
    if (!$item || $item['type'] !== 'file') {
        http_response_code(404);
        // echo json_encode(['error'=>'Not found or not a file']);
        return ['error'=>'Not found or not a file'];
    }
    $item = iterator_to_array($item);

    $rel = $item['contentPath'] ?? '';
    $path = fullPath($rel);
    if (!file_exists($path)) {
        http_response_code(404);
        // echo json_encode(['error'=>'No content']);
        return ['error'=>'No content'];
    }

    header('Content-Type: application/octet-stream');
    header('Content-Disposition: attachment; filename="'.basename($item['name']).'"');
    readfile($path);
    exit;
}

function FileProvider_CreateItem($user) {
    global $FileProviderFiles;
    $body   = json_decode(file_get_contents('php://input'), true);
    $parent = isset($body['parentId']) ? decodeId($body['parentId']) : null;

    $new = [
      'id'         => uniqid(),
      'parentId'   => $parent,
      'GUUID'      => $user['GeneratedUID'],
      'name'       => $body['name'],
      'type'       => $body['type'], // "file" or "folder"
      'createdAt'  => time(),
      'updatedAt'  => time(),
      // contentPath is NULL until someone uploads data
    ];
    $FileProviderFiles->insertOne($new);

    http_response_code(201);
    header('Content-Type: application/json');
    $new = FileProvider_FileStruct($new);
    return $new;
}

function FileProvider_UpdateItem($encodedId, $user) {
    global $FileProviderFiles;
    $id     = decodeId($encodedId);
    $filter = ['id' => $id, 'GUUID' => $user['GeneratedUID']];

    // 1) Fetch existing item
    $item = $FileProviderFiles->findOne($filter);
    if (!$item) {
        http_response_code(404);
        return ['error' => 'Not found'];
    }
    $item = iterator_to_array($item);
    // 2) Decode request body
    $body   = json_decode(file_get_contents('php://input'), true);
    $update = [];

    // 3) Handle each supported field
    if (isset($body['name'])) {
        $update['name'] = $body['name'];
    }
    if (array_key_exists('parentId', $body)) {
        $update['parentId'] = $body['parentId']
            ? decodeId($body['parentId'])
            : null;
    }
    if (isset($body['lastUsedDate'])) {
        $update['lastUsedDate'] = (int)$body['lastUsedDate'];
    }
    if (isset($body['creationDate'])) {
        $update['createdAt'] = (int)$body['creationDate'];
    }
    if (isset($body['contentModificationDate'])) {
        $update['contentModificationDate'] = (int)$body['contentModificationDate'];
    }
    if (isset($body['tagData'])) {
        // Expecting a base64‑encoded string of tag data
        $update['tagData'] = base64_decode($body['tagData']);
    }
    if (isset($body['favoriteRank'])) {
        $update['favoriteRank'] = (int)$body['favoriteRank'];
    }
    if (isset($body['fileSystemFlags'])) {
        $update['fileSystemFlags'] = (int)$body['fileSystemFlags'];
    }
    if (!empty($body['extendedAttributes']) && is_array($body['extendedAttributes'])) {
        // e.g. { "com.example.foo": "bar", ... }
        $update['extendedAttributes'] = $body['extendedAttributes'];
    }
    if (!empty($body['typeAndCreator']) && is_array($body['typeAndCreator'])) {
        // expecting ["type"=>"ttxt","creator"=>"abcd"]
        $update['typeAndCreator'] = $body['typeAndCreator'];
    }

    // 4) Bail if nothing to change
    if (empty($update)) {
        http_response_code(400);
        return ['error' => 'Nothing to update'];
    }

    // 5) Always bump your generic updatedAt
    $update['updatedAt'] = time();

    // 6) Perform the Mongo update
    $FileProviderFiles->updateOne(
        $filter,
        ['$set' => $update]
    );

    // 7) Merge and return the new item
    $item = array_merge($item, $update);
    header('Content-Type: application/json');
    // echo json_encode($item);
    $item = FileProvider_FileStruct($item);
    return $item;
}


function FileProvider_DeleteItem($encodedId, $user) {
    global $FileProviderFiles;
    $id = decodeId($encodedId);
    $item = $FileProviderFiles->findOne(['id'=>$id,'GUUID'=>$user['GeneratedUID']]);
    if (!$item) {
        http_response_code(404);
        // echo json_encode(['error'=>'Not found']);
        return ['error'=>'Not found'];
    }
    $item = iterator_to_array($item);
    // if a file, remove from disk
    if ($item['type']==='file' && !empty($item['contentPath'])) {
        $p = fullPath($item['contentPath']);
        if (file_exists($p)) unlink($p);
    }

    $FileProviderFiles->deleteOne(['id'=>$id,'GUUID'=>$user['GeneratedUID']]);
    http_response_code(204);
}

function FileProvider_UploadContent($encodedId, $user) {
    global $FileProviderFiles;
    $id   = decodeId($encodedId);
    $item = $FileProviderFiles->findOne(['id'=>$id, 'GUUID'=>$user['GeneratedUID']]);
    if (!$item || $item['type']!=='file') {
        // http_response_code(404); echo json_encode(['error'=>'Not found or not a file']); return;
        return ['error'=>'Not found or not a file'];
    }
    $item = iterator_to_array($item);
    if (empty($_FILES['file'])) {
        // http_response_code(400); echo json_encode(['error'=>'No file uploaded']); return;
        return ['error'=>'No file uploaded'];
    }

    $tmp     = $_FILES['file']['tmp_name'];
    $root    = uploadRoot();
    $name    = "{$id}_" . basename($_FILES['file']['name']);
    $destRel = $name;
    $destAbs = "$root" . DIRECTORY_SEPARATOR . $destRel;

    if (!move_uploaded_file($tmp, $destAbs)) {
        // http_response_code(500); echo json_encode(['error'=>'Upload failed']); return;
        return ['error'=>'Upload failed'];
    }

    // save **relative** path in DB
    $metadata = [
      'contentPath' => $destRel,
      'updatedAt'   => time(),
    ];
    $FileProviderFiles->updateOne(
      ['id'=>$id,'GUUID'=>$user['GeneratedUID']],
      ['$set'=>$metadata]
    );

    $updated = array_merge($item, $metadata);
    header('Content-Type: application/json');
    // echo json_encode($updated);
    $updated = FileProvider_FileStruct($updated);
    return $updated;
}


// // ---- Route map (example) ----
// $paths = [
//   "GET"    => [
//     "FileProvider/items"                      => "FileProvider_Files_Root",
//     "FileProvider/items/{String}"             => "FileProvider_GetItem",
//     "FileProvider/items/{String}/content"     => "FileProvider_GetContent",
//   ],
//   "POST"   => [
//     "FileProvider/items"                      => "FileProvider_CreateItem",
//   ],
//   "PUT"    => [
//     "FileProvider/items/{String}"             => "FileProvider_UpdateItem",
//     "FileProvider/items/{String}/content"     => "FileProvider_UploadContent",
//   ],
//   "DELETE" => [
//     "FileProvider/items/{String}"             => "FileProvider_DeleteItem",
//   ],
// ];

// // Your existing FileProvider_Files and FileProvider_Files_Root go alongside these.

// // Don’t forget to wire your router so that each function gets `$user` injected (from auth).



function FileProvider_FileStruct($item) {

    // if the parentId is Trash then set Trash to true
    if ($item['parentId'] === "NSFileProviderTrashContainerItemIdentifier") {
        $item['Trash'] = true;
    } 

    return  $item;
}
