#
# Create a Shiny App asset and Deploy in Cloud Pak for Data
#
# This R script takes your Shiny R code from your local working directory,
# stores it as a "Shiny App" asset in the deployment space,
# and launches the corresponding app deployment.
#
# The script adds a new Shiny asset and a new deployment to the deployment space.
# You have to delete the objects manually when they are not needed anymore.
#
# The implementation calls the CP4D RESTful API. No other library needed.


# This sample code is provided "as is", without warranty of any kind.


# How to use this script in Cloud Pak for Data
#
# 0. Upload this script to RStudio in Cloud Pak for Data
# 1. In RStudio Files browser set the working directory to point to the code of your Shiny app 
# 2. Set parameters below incl the name of your CP4D deployment space
# 3. Run the whole script
#
#
# Set your parameters:
#
# Set the working directory to point to the code of your Shiny app 
setwd("/userfs/ListDirApp")     # or set the working dir in the file browser of RStudio
APP_NAME="ListDirApp"       # Name to be used for the new app
SPACE_NAME="RStudio-deployments"       # Your existing Deployment Space
URL_HOST = Sys.getenv("RUNTIME_ENV_APSX_URL")   # URL of your CP4D server
# The environment variable RUNTIME_ENV_APSX_URL is already predefined
# if you run this script in CP4D RStudio.

################################

library(httr)


# little utility function to check httr result codes
httr_check <- function(label,r,rc){
  print(label) 
  if(r$status_code>rc) {
    print(c(label,"Error",r$status_code))
    print(httr::content(r))
  }
  stopifnot(r$status_code<=rc)
  print("ok")
}


# GET /v2/spaces?name={SPACE_NAME}
url <- paste0(Sys.getenv("RUNTIME_ENV_APSX_URL"),"/v2/spaces?name=",URLencode(SPACE_NAME))
r <- GET(url,add_headers(Authorization = paste("Bearer",Sys.getenv("USER_ACCESS_TOKEN"))))
httr_check(paste("get space",SPACE_NAME),r,200)
rjson = httr::content(r, type = 'application/json', simplifyDataFrame = TRUE)
SPACE_ID = rjson$resources$metadata$id

if(is.null(SPACE_ID)) {
  stop(c("Deployment Space '",SPACE_NAME,"' not found"), call. = FALSE)
}


# Check if the working directory has Shiny app files
found = FALSE; 
standard_app_files = c("app.R","server.R","app.Rmd","index.Rmd")
for ( fname in standard_app_files ) { found = found | file.exists(fname) }
if (!found ) {
  print("WARNING !!!",quote=FALSE)
  print("did not find any standard app file in the working directory",quote=FALSE)
  cat("checked", paste(standard_app_files),"\n")
  print("Make sure your working directory is set to the directory of the Shiny app!",quote=FALSE)
  if ( getwd() == Sys.getenv("HOME")) { stop(c("Working directory'",getwd(),"' is not a Shiny app directory"), call. = FALSE)}
}



# Upload Shiny app as zip file
#
# cpdcurl PUT "/v2/asset_files/shiny_asset/MyAppName.zip?space_id=$SPACE_ID" 
#      -F file=@MyAppName.zip
#
app_zip = paste0("/tmp/",APP_NAME,".zip")
ziplog = system2("zip",args=c("-FSr",app_zip,"."), stdout = TRUE, stderr = TRUE)
print(ziplog)
writeLines( system2("unzip",args=c("-l",app_zip), stdout = TRUE, stderr = TRUE) )

# set unique name for uploaded file, using  epoch seconds
uploaded_app_zip = paste0(APP_NAME,as.numeric(Sys.time()),".zip")
url <- paste0(URL_HOST,"/v2/asset_files/shiny_asset/",uploaded_app_zip,"?space_id=",SPACE_ID)
print(url)
# attribute name in body must be 'file'
r <- PUT(url, body=list(file=upload_file(path=app_zip, type="application/zip")),
         add_headers(Authorization = paste("Bearer",Sys.getenv("USER_ACCESS_TOKEN"))))
httr_check("Upload",r,201)
print(httr::content(r))


# Get software spec for R4.2 in CP4D >= v4.6
#
# cpdcurl GET "/v2/software_specifications?name=rstudio_r4.2"
# old 3.6 spec is "shiny-r3.6"
url <- paste0(Sys.getenv("RUNTIME_ENV_APSX_URL"),"/v2/software_specifications?name=rstudio_r4.2")
r <- GET(url,add_headers(Authorization = paste("Bearer",Sys.getenv("USER_ACCESS_TOKEN"))))
httr_check("software spec",r,200)
rjson = httr::content(r, type = 'application/json', simplifyDataFrame = TRUE)
swspec_id = rjson$resources$metadata$asset_id  # might be NULL when rstudio_r4.2 is not avail
if (!is.null(swspec_id)) print(c("rstudio_r4.2",swspec_id))


##########################
# Create Asset
url <- paste0(Sys.getenv("RUNTIME_ENV_APSX_URL"),"/v2/assets?space_id=",SPACE_ID)
body <- list(
  metadata = list( name = APP_NAME, asset_type = "shiny_asset", origin_country = "de" ),
  entity = list( ),
  attachments = list( list(asset_type="shiny_asset",mime="application/zip",object_key=paste0("shiny_asset/",uploaded_app_zip)))
)
if (!is.null(swspec_id)) {
  body["entity"] <- list(entity = list( shiny_asset = list( software_spec = list(base_id=swspec_id)) ))
}
#print(body)
r <- POST(url, body = body, encode = "json",
          add_headers(Authorization = paste("Bearer",Sys.getenv("USER_ACCESS_TOKEN")))
)
httr_check("Asset",r,201)
rjson = httr::content(r, type = 'application/json', simplifyDataFrame = TRUE)
print(rjson$metadata$asset_id)
ASSET_ID = rjson$metadata$asset_id


##########################
print("Check access to WML server and space")
#
url <- paste0(URL_HOST,"/ml/v4/deployments?type=r_shiny&limit=1&version=2023-04-01&space_id=",SPACE_ID)
print(url)
r <- GET(url,add_headers(Authorization = paste("Bearer",Sys.getenv("USER_ACCESS_TOKEN"))))
httr_check("WML server",r,200)


##########################
print("Create deployment")
#
url <- paste0(URL_HOST,"/ml/v4/deployments?version=2023-04-01&space_id=",SPACE_ID)

body <- list(
  name = APP_NAME,
  space_id = SPACE_ID,
  asset = list( id = ASSET_ID ),
  r_shiny = list(
    # parameters = list( serving_name="myapp_serving_name123" ),
    # parameters = list( auto_mount = FALSE ),   # default is TRUE
    # parameters = list( mounts = list( "/mnts/customlogs" ) ),
    authentication = "members_of_deployment_space"
  ),
  hardware_spec =  list( name = "XXS" )
)
# Authentication, Allowable values: [anyone_with_url,any_valid_user,members_of_deployment_space]
# https://cloud.ibm.com/apidocs/machine-learning-cp#deployments-create
#
# Using Storage Volumes in Shiny
# https://www.ibm.com/docs/en/cloud-paks/cp-data/4.7.x?topic=deployments-deploying-shiny-apps#connect-storage-vol

r <- POST(url, body = body, encode = "json",
          add_headers(Authorization = paste("Bearer",Sys.getenv("USER_ACCESS_TOKEN")))
)
httr_check("Deploy",r,202)
rjson = httr::content(r, type = 'application/json', simplifyDataFrame = TRUE)
print(rjson$entity$status)   # "initializing"

deployment_id = rjson$entity$asset$id

# WML API
# DELETE /ml/v4/deployments/{deployment_id}