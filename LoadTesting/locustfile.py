# Assumes use of the SyncServer_SharedImages database.

from locust import HttpLocust, Locust, TaskSet, task
import json
import uuid
import random

with open('accessTokens.json') as json_file:
    tokens = json.load(json_file)
    user1AccessToken = tokens["user1AccessToken"]
    user2AccessToken = tokens["user2AccessToken"]

user1Id = 1
user2Id = 2

user1SharingGroups = []
user2SharingGroups = []

def headers(deviceUUID, userAccessToken):
    return {
        "X-token-type": "GoogleToken",
        "access_token": userAccessToken,
        "SyncServer-Device-UUID": deviceUUID
    }

def makeParams(dict):
    result = ""
    for key, value in dict.items():
        if len(result) == 0:
            result += "?"
        else:
            result += "&"
        result += key + "=" + value
    return result

# Returns an array of sharingGroupUUID's to which the user belongs.
def sharingGroupsForUser(indexResponse, userId):
    sharingGroups = indexResponse["sharingGroups"]
    result = []
    for sharingGroup in sharingGroups:
        sharingGroupUsers = sharingGroup["sharingGroupUsers"]
        for sharingGroupUser in sharingGroupUsers:
            if sharingGroupUser["userId"] == userId:
                result.append(sharingGroup["sharingGroupUUID"])
    return result

# Pass in two arrays.
def sharingGroupIntersection(sharingGroups1, sharingGroup2):
    return list(set(sharingGroups1) & set(sharingGroup2))

def sharingGroupForUser(userId):
    if userId == user1Id:
        return random.choice(user1SharingGroups)
    else:
        return random.choice(user2SharingGroups)

def randomUser():
    return random.choice([user1Id, user2Id])

def accessTokenForUser(userId):
    if userId == user1Id:
        return user1AccessToken
    else:
        return user2AccessToken

class MyTaskSet(TaskSet):
    # This gets run once when the task set starts.
    def setup(self):
        global user1SharingGroups, user2SharingGroups
        
        response = self.generalIndex(user1AccessToken)
        user1SharingGroups = sharingGroupsForUser(response, user1Id)
        print("User 1 sharing groups: " + ''.join(user1SharingGroups))
        response = self.generalIndex(user2AccessToken)
        user2SharingGroups = sharingGroupsForUser(response, user2Id)
        print("User 2 sharing groups: " + ''.join(user2SharingGroups))

    # Returns the new sharingGroupUUID, or None if the request fails.
    def createSharingGroup(self, accessToken):
        newSharingGroupUUID = str(uuid.uuid1())
        params = makeParams({
            "sharingGroupUUID": newSharingGroupUUID
        })
        deviceUUID = str(uuid.uuid1())
        resp = self.client.post("/CreateSharingGroup/" + params, headers=headers(deviceUUID, accessToken))
        if resp.status_code not in range(200, 300):
            print("Error on CreateSharingGroup POST")
            return None
        return newSharingGroupUUID
    
    # Returns sharingInvitationUUID, or None if the request fails.
    def createSharingInvitation(self, accessToken, sharingGroupUUID):
        params = makeParams({
            "sharingGroupUUID": sharingGroupUUID,
            "permission": "admin"
        })
        deviceUUID = str(uuid.uuid1())
        resp = self.client.post("/CreateSharingInvitation/" + params, headers=headers(deviceUUID, accessToken))
        if resp.status_code not in range(200, 300):
            print("Error on CreateSharingInvitation POST")
            return None
        invitationResponse = json.loads(resp.text)
        sharingInvitationUUID = invitationResponse.get("sharingInvitationUUID")
        return sharingInvitationUUID

    # This needs to be executed by a different user than the creating user.
    # Returns sharingGroupUUID, or None if the request fails.
    def redeemSharingInvitation(self, accessToken, sharingInvitationUUID):
        params = makeParams({
            "sharingInvitationUUID": sharingInvitationUUID,
            "cloudFolderName": "Local.SharedImages.Folder"
        })
        deviceUUID = str(uuid.uuid1())
        resp = self.client.post("/RedeemSharingInvitation/" + params, headers=headers(deviceUUID, accessToken))
        if resp.status_code not in range(200, 300):
            print("Error on RedeemSharingInvitation POST")
            return None
        redeemResponse = json.loads(resp.text)
        sharingGroupUUID = redeemResponse.get("sharingGroupUUID")
        return sharingGroupUUID
        
    def generalIndex(self, accessToken):
        deviceUUID = str(uuid.uuid1())
        resp = self.client.get("/Index/", headers=headers(deviceUUID, accessToken))
        if resp.status_code not in range(200, 300):
            print("Error on Index GET")
            return None
        return json.loads(resp.text)
        
    def indexSharingGroup(self, userAccessToken, deviceUUID, sharingGroupUUID):
        params = makeParams({"sharingGroupUUID": sharingGroupUUID})
        resp = self.client.get("/Index/" + params, headers=headers(deviceUUID, userAccessToken))
        if resp.status_code not in range(200, 300):
            print("Error on Index GET")
            return None
        indexResponse = json.loads(resp.text)
        return indexResponse

    # Returns True iff operation works
    def doneUploads(self, accessToken, masterVersion, deviceUUID, sharingGroupUUID, numTries=0, maxTries=3):
        if numTries > maxTries:
            print("Error on DoneUploads: Exceeded number of retries")
            return False
        
        params = makeParams({
            "sharingGroupUUID": sharingGroupUUID,
            "masterVersion": str(masterVersion)
        })
        resp = self.client.post("/DoneUploads/" + params, headers=headers(deviceUUID, accessToken))
        if resp.status_code not in range(200, 300):
            print("Error on DoneUploads POST")
            return False
            
        body = json.loads(resp.text)
        masterVersion = body.get("masterVersionUpdate")
        if masterVersion is not None:
            return self.doneUploads(accessToken, masterVersion, deviceUUID, sharingGroupUUID, numTries + 1)
        
        return True
    
    # Returns the updated masterVersion if there is one or None.
    def getMasterVersionUpdateInHeader(self, resp):
        respParams = None
        if resp.headers.get("syncserver-message-params") is None:
            print("Error on UploadFile: No header params")
            return None
        respParams = resp.headers["syncserver-message-params"]
        respParamsJSON = json.loads(respParams)
        masterVersion = respParamsJSON.get("masterVersionUpdate")
        if masterVersion is not None:
            return masterVersion
        return None

    # Returns True iff successful.
    def downloadFileAux(self, accessToken, deviceUUID, paramDict, masterVersion, numTries=0, maxTries=3):
        if numTries > maxTries:
            print("Error on DownloadFile: Exceeded number of retries")
            return False

        paramDict["masterVersion"] = str(masterVersion)
        params = makeParams(paramDict)
        resp = self.client.get("/DownloadFile/" + params, headers=headers(deviceUUID, accessToken))
        if resp.status_code not in range(200, 300):
            print("Error on DownloadFile GET")
            return False

        masterVersion = self.getMasterVersionUpdateInHeader(resp)
        if masterVersion is not None:
            return self.downloadFileAux(accessToken, deviceUUID, paramDict, masterVersion, numTries + 1)

        return True

    # Returns working param dictioary iff successful; None if failure.
    def uploadFileWithRetries(self, accessToken, deviceUUID, data, paramDict, masterVersion, numTries=0, maxTries=3):
        if numTries > maxTries:
            print("Error on UploadFile: Exceeded number of retries")
            return None
        
        paramDict["masterVersion"] = str(masterVersion)
        params = makeParams(paramDict)
        resp = self.client.post("/UploadFile/" + params, data=data, headers=headers(deviceUUID, accessToken))
        if resp.status_code not in range(200, 300):
            print("Error on UploadFile")
            return None
            
        masterVersion = self.getMasterVersionUpdateInHeader(resp)
        if masterVersion is not None:
            return self.uploadFileWithRetries(accessToken, deviceUUID, data, paramDict, masterVersion, numTries + 1)

        return paramDict

    # Return working upload dictionary if upload with DoneUploads works; None otherwise.
    def uploadFileAux(self, accessToken, deviceUUID, sharingGroupUUID):
        indexResponse = self.indexSharingGroup(accessToken, deviceUUID, sharingGroupUUID)
        if indexResponse is None:
            return None
        
        masterVersion = indexResponse["masterVersion"]

        fileUUID = str(uuid.uuid1())
        paramDict = {
            "fileUUID": fileUUID,
            "sharingGroupUUID": sharingGroupUUID,
            "fileVersion": "0",
            "mimeType": "image/jpeg",
            "checkSum": "6B5B722C95BC6D5A023B6236486EBB8C".lower()
        }

        data = None
        with open("IMG_2963.jpeg", "r") as f:
            data = f.read()

        uploadResult = self.uploadFileWithRetries(accessToken, deviceUUID, data, paramDict, masterVersion)
        if uploadResult is None:
            return None

        if self.doneUploads(accessToken, masterVersion, deviceUUID, sharingGroupUUID):
            return uploadResult
        else:
            return None

    # Return True iff succeeds (no DoneUploads)
    def deleteFileAux(self, accessToken, deviceUUID, paramDict, masterVersion, numTries=0, maxTries=3):
        if numTries > maxTries:
            print("Error on DeleteFile: Exceeded number of retries")
            return False
        
        paramDict["masterVersion"] = str(masterVersion)
        params = makeParams(paramDict)
        resp = self.client.delete("/UploadDeletion/" + params, headers=headers(deviceUUID, accessToken))
        if resp.status_code not in range(200, 300):
            print("Error on DeleteFile")
            return False
        
        body = json.loads(resp.text)
        masterVersion = body.get("masterVersionUpdate")
        if masterVersion is not None:
            return self.deleteFileAux(accessToken, deviceUUID, paramDict, masterVersion, numTries + 1)
            
        return True
    
    @task
    def downloadFile(self):
        deviceUUID = str(uuid.uuid1())
        userId = randomUser()
        sharingGroupUUID = sharingGroupForUser(userId)
        accessToken = accessTokenForUser(userId)
        indexResponse = self.indexSharingGroup(accessToken, deviceUUID, sharingGroupUUID)
        if indexResponse is None:
            return
        notDeleted = list(filter(lambda file: not file["deleted"], indexResponse["fileIndex"]))
        exampleFile = notDeleted[0]
        masterVersion = indexResponse["masterVersion"]
        paramDict = {
            "sharingGroupUUID": sharingGroupUUID,
            "fileUUID": exampleFile["fileUUID"],
            "fileVersion": str(exampleFile["fileVersion"])
        }

        if exampleFile.get("appMetaDataVersion") is not None:
            paramDict["appMetaDataVersion"] = str(exampleFile["appMetaDataVersion"])

        if not self.downloadFileAux(accessToken, deviceUUID, paramDict, masterVersion):
            print("ERROR DownloadFile GET")
            return

        print("SUCCESS DownloadFile GET")

    @task
    def index(self):
        userId = randomUser()
        accessToken = accessTokenForUser(userId)
        self.generalIndex(accessToken)

    @task
    def uploadFile(self):
        userId = randomUser()
        accessToken = accessTokenForUser(userId)
        sharingGroupUUID = sharingGroupForUser(userId)
        deviceUUID = str(uuid.uuid1())
        if self.uploadFileAux(accessToken, deviceUUID, sharingGroupUUID) is None:
            print("Error on UploadFile")
            return
        print("SUCCESS on UploadFile")

    @task
    def deleteFile(self):
        userId = randomUser()
        sharingGroupUUID = sharingGroupForUser(userId)
        accessToken = accessTokenForUser(userId)
        deviceUUID = str(uuid.uuid1())
        uploadResult = self.uploadFileAux(accessToken, deviceUUID, sharingGroupUUID)
        if uploadResult is None:
            print("Error on DeleteFile: Upload failed")
            return

        masterVersion = uploadResult["masterVersion"]
        # Need to +1 masterVersion because the value we have is after the DoneUploads with the upload.
        masterVersion = int(masterVersion)
        masterVersion += 1
        masterVersion = str(masterVersion)

        paramDict = {
            "fileUUID": uploadResult["fileUUID"],
            "sharingGroupUUID": uploadResult["sharingGroupUUID"],
            "fileVersion": uploadResult["fileVersion"]
        }

        if not self.deleteFileAux(accessToken, deviceUUID, paramDict, masterVersion):
            print("Error on DeleteFile")
            return

        if not self.doneUploads(accessToken, masterVersion, deviceUUID, sharingGroupUUID):
            print("Error on DoneUploads/DeleteFile")
            return

        print("SUCCESS on DeleteFile")

class MyLocust(HttpLocust):
    task_set = MyTaskSet
    
    # https://docs.locust.io/en/stable/writing-a-locustfile.html
    # These are the minimum and maximum time respectively, in milliseconds, that a simulated user will wait between executing each task.
    min_wait = 5000
    max_wait = 15000
