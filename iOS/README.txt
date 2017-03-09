Client: The iOS client interface to the SyncServer server
	The folder `SignIn` within the Client directory is special-- the files within it are not part of the library but must be separately brought into your project. This is both so that you are not forced to use all of the required libraries (e.g., for Google SignIn) and because some of those libraries (e.g., Google SignIn) are, at the time of this writing, are static and cannot be transitively linked in a Cocoapod.
	
Example: An example of using this iOS client, along with tests for the Client interface.

SharedImages: A second, more interesting example, of using this iOS client.
