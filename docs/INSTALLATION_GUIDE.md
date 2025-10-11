
## Installation

Well, looks like someone wants to install wisp.  
Great! Let's start.

Grab some [pre-built binaries](https://github.com/wizeshi/wisp/releases) or [build them yourself](https://github.com/wizeshi/wisp/blob/master/docs/RUN_LOCALLY.md).  
Then, run the setup and voilà, it's installed.  

No, but I know you aren't here because of that.  
There are a couple more steps to go.

The following steps are shown in the app, so you don't need to follow from here.

### To set up the Spotify API:
- Go to the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) 
- Log in to your spotify account
- Click "Create App"
- Input any app name and description
- Add the following redirect URI: ```wisp-login://callback```
- Check "Web API" and accept Spotify's Terms of Use
- Copy your Client ID and Client Secret
- And then, either:
  - Input the credentials in the initial setup,
  - Or go to the App's settings (top-right), select the Pencil Icon to the right of the Spotify Account Row, and input the credentials there.
- Finally, login to your Spotify Account


### To set up the Youtube API:
- Go to the [Google Cloud Console](https://console.cloud.google.com/)
- Open the projects pop-up (top-right or Control + O)
- Either create a new project or reuse an existing one
- Go to the Sidebar, then "APIs & Services", and then "Library"
- Search for the Youtube data v3 API and enable it 
- Go to "Credentials", then "Create Credentials" and select "OAuth client ID"
- Select "Web App" and input any name
- Click "Add URI" under "Authorized redirect URIs", and input ```http://127.0.0.1:8080/callback```
- Copy your Client ID and Client Secret
- Then select your newly created OAuth Client
- Select "Audience" in the sidebar
- Scroll down until you find the "Test users" section
- Click "Add Users" and add your Google Account's email there (else, the API won't work)
- And then, either:
  - Input the credentials in the initial setup,
  - Or go to the App's settings (top-right), select the Pencil Icon to the right of the Youtube Account Row, and input the credentials there.
- Finally, login to your Google Account
    