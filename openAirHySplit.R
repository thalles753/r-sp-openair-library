####################################################
####################################################
####################################################

ReadFiles <- function( working_dir, ID, dates, tz) 
{
  combine.file.name <- paste("Rcombined_", ID, ".txt", sep="")
  dump.file.name <- paste("tdump_", ID, "_", "*", sep="")
  
  # find tdump files
  files <- list.files(path = working_dir, pattern = paste("tdump_", ID, sep=""))
  
  output <- file(combine.file.name, 'w')
  
  if(length(dates) != length(files)){
    print(length(dates))
    print(length(files))
    # cleanWD(hy.path, ID)
    stop("Please, make sure that all required meteorological files are available.")
  }
  
  # read through them all, ignoring 1st 7 lines
  for (i in files){
    input <- readLines(i)
    input <- input[-c(1:7)] # delete header
    writeLines(input, output)
  }
  close(output)
  
  # read the combined txt file
  
  traj <- read.table(file.path(working_dir, combine.file.name), 
                     header = FALSE)
  
  traj <- subset(traj, select = -c(V2, V7, V8))
  
  traj <- rename(traj, c(V1 = "receptor", V3 = "year", V4 = "month", V5 = "day",
                         V6 = "hour", V9 = "hour.inc", V10 = "lat", V11 = "lon",
                         V12 = "height", V13 = "pressure"))
  
  # hysplit uses 2-digit years ...
  year <- traj$year[1]
  
  if (year < 50) {
    traj$year <- traj$year + 2000 
  } else { 
    traj$year <- traj$year + 1900
  }
  
  # Setup the Canada, ON timezone
  traj$date2 <- with(traj, ISOdatetime(year, month, day, hour, min = 0, 
                                       sec = 0, tz = tz)) 
  
  # arrival time
  traj$date <- traj$date2 - 3600 * traj$hour.inc
  traj
}

AddMetFiles <- function(month, Year, met, script.file, control.file) 
{
  ## if month is one, need previous year and month = 12
  if (month == 0) {
    month <- 12
    Year <- as.numeric(Year) - 1
  }
  
  if (month < 10) {
    month <- paste("0", month, sep = "")
  }
  
  ## add first line
  line <- paste("echo", met, ">>", control.file, sep=" ")
  cat(line, file = script.file, sep = "\n")
  
  line <- paste("echo RP", Year, month, ".gbl >> ", control.file, sep = "")
  cat(line, file = script.file, sep = "\n")
}

ProcTraj <- function(lat = 51.5, lon = -0.1, year = 2010, 
                     hour.interval = 1, name = "london",
                     start.hour = "00:00", end.hour="23:00",
                     met, 
                     out, 
                     hours = 12, height = 100, 
                     hy.path = "/home/user/Desktop/hysplit/trunk/", ID,
                     dates, script.name="test",
                     add.new.column = F, new.column.name, new.column.value,
                     tz="GMT", clean.files=T ) {
  
  # This function setsup and executes hysplit. The ProcTraj function is 
  # designed for parallel execution.
  #
  # Args:
  #   lat: Numeric: Initial point's Latitude.
  #   lon: Numeric: Initial point's Longitude.
  #   year: year: Integer: It specifies the year of the trajectory calculation 
  #         e.g. 1978. This year must agree with the year of the meteorological data file.
  #   hour.interval: Integer: This value specifies the interval when each trajectory will be calculated.
  #   name: String: Name of the trajectory endpoints file.
  #   start.hour: String: Specifies the START hour of the simulation. An example would be: start.hour = "12:00"
  #   end.hour: String: Specifies the END hour of the simulation. An example would be: start.hour = "14:00"
  #   met: String: Directory location of the meteorological file. More information 
  #        concerning to meteorological files can be found in 
  #        http://www.meteozone.com/home/tutorial/html/meteo_ftp.html.  
  #   out: String: Directory location to which the [output.RData] trajectory end-point 
  #        files will be written. Always terminate with the appropriate slash
  #        (\ or /). If this argument is omitted, the output will only be returned by the
  #        function instead of be saved on the local memory.
  #   hours: Integer: Total run time. It specifies the duration of the calculation 
  #          in hours. Backward calculations are entered as negative values. 
  #          A backward trajectory starts from the trajectory termination point 
  #          and proceeds upwind. Meteorological data are processed in reverse-time order. 
  #          Because only two additional meteorological files are loaded, 
  #          one for the last and another for the next month, it is recommended 
  #          a maximum trajectory length of 24 hours.
  #
  #   height: numeric: The initial trajectories height. Height is entered as meters above ground-level.
  #   
  #   hy.path: String: The local path where HySplit is located. Example, for 
  #            linux/OS X Operating Systems "/home/user/Desktop/hysplit/trunk/"
  #
  #   ID: Integer: Process ID. When called in Parallel, the ID argument ensures 
  #       that each process will deal with separate set of files preventing race 
  #       condition problems among different processes. 
  #
  #   dates: vector containg all the dates that will be calculated by hysplit.
  #   tz: String: This argument specifies the Time Zone to be applied, e.g. "GMT"
  #   clean.files: Boolean: If TRUE, all the files created by HySplit will be deleted. 
  #
  # Returns:
  #   It generates and saves an R file with all the trajectories that have been 
  #   calculated by HySplit
  
  # set up the script extension string
  script.extension <- ".sh"
  OS <- "unix"
  
  # check the Operating System
  if(.Platform$OS.type == "windows"){
    script.extension <- ".bat"
    OS <- "windows"
  }
  
  # changes the R working directory to the hysplit working directory
  hy.split.wd <- file.path(hy.path, "working" )
  hy.split.wd <- normalizePath(hy.split.wd)
  setwd(hy.split.wd)
  
  # process folder name
  folder.name = paste( "process_", ID, sep="")
  
  # each process creates its own folders to store necessary files
  process.working.dir <- file.path(hy.split.wd, folder.name) # path to process working directory
  dir.create(process.working.dir, showWarnings = FALSE)
  process.working.dir <- normalizePath(process.working.dir)
  
  # each process changes the R working directory to its own folder
  setwd(process.working.dir)
  
  # build HySplit exec dir directory path
  hy.split.exec.dir <- file.path(hy.path, "exec", "hyts_std")
  
  # link all ASC files from the bdyfiles/ directory to the process working directory
  # this spep is requered in order to run hysplit
  bdyfiles.path <- file.path(hy.path, "bdyfiles")
    
  symb.link.files <- list.files(path = bdyfiles.path)
  
  for( i in 1:length(symb.link.files) ){
    from <- normalizePath( file.path(bdyfiles.path, symb.link.files[[i]] ) )
    to <-  file.path(process.working.dir, symb.link.files[[i]])
    file.copy( from, to)
  }
  
  # generate an unique CONTROL file name for each instance of HYSPLIT
  control.file.number <- 1 # this number is the extension of the CONTROL file
  
  # hours is the back trajectory time e.g. 96 = 4-day back trajectory
  # height is start height (m)
  lapply(c("openair", "plyr", "reshape2"), require, character.only = TRUE)
  
  # insure that each HySplit process will create an individual script file
  # which allows parallel processing 
  script.name <- paste(script.name, "_", ID, script.extension, sep="")

  ###################
  # process the dates
  dates.and.times <- 
                laply( .data = dates, 
                   .fun=function(d) { 
                     start.day <- paste(d, start.hour, sep=" ")
                     end.day <- paste(d, end.hour, sep=" ")
                     
                     posix.date <- seq(as.POSIXct(start.day, tz), as.POSIXct(end.day, tz), by = paste(hour.interval, "hour", sep=" "))
                     
                     as.character(posix.date)
                   })

  
  ###################
  hour.interval <- paste( hour.interval, "hour", sep=" ")
  
   
  for (i in 1:length(dates.and.times)) {
    control.file <- "CONTROL"
    
    date <- as.POSIXct(dates.and.times[i], tz=tz)
    
    # CONTROL FILE extension
    # format: [1-9]+_[1-9]+...
    # the first number represents the interation ID, it is necessary 
    # to insure that each thread will create a separate group of CONTROl.files
    # the second number represents the ID of the trajectory, which can be 
    # determined by the number of trajectories for each individual point
    control.file.extension <- paste(as.character(ID), "_", control.file.number, sep="")
    
    # create CONTROL file name
    control.file <- paste(control.file, control.file.extension, sep=".")
    
    year <- format(date, "%y")
    Year <- format(date, "%Y") # long format
    month <- format(date, "%m")
    day <- format(date, "%d")
    hour <- format(date, "%H")
    
    # create file connection
    script.file <- file(script.name, "w")  # open an output file connection
    
    if(OS == "unix"){
      cat("#!/bin/bash", file= script.file, sep="\n")
    }
    
    line <- paste("echo", year, month, day, hour, ">", control.file, sep=" ")
    cat( line, file = script.file, sep = "\n")
    
    line <- paste("echo 1 >>", control.file, sep=" " )
    cat(line, file = script.file, sep="\n")
    
    line <- paste("echo", lat, lon, height, ">>", control.file, sep=" ")
    cat(line, file = script.file, sep="\n")
    
    line <- paste("echo", hours, ">>", control.file, sep=" ")
    cat(line, file = script.file, sep="\n")
    
    line <- paste("echo 0 >> ", control.file, "\n",
                  "echo 10000.0 >> ", control.file, "\n",
                  "echo 3 >> ", control.file, "\n",
                  sep="")
    
    cat(line, file = script.file, sep="")
    
    ## processing always assumes 3 months of met for consistent tdump files
    months <- as.numeric(unique(format(date, "%m")))
    months <- c(months, months + 1:2)
    months <- months - 1 ## to make sure we get the start of the previous year
    months <- months[months <= 12]
    #print(months)
    if (length(months) == 2) {
      months <- c(min(months) - 1, months)
    }
    
    for (i in 1:3) {
      AddMetFiles(months[i], Year, met, script.file, control.file)
    }
    
    line <- paste("echo ./ >>", control.file, sep=" ")
    cat(line, file = script.file, sep="\n")
    
    line <- paste("echo tdump", "_", ID, "_", year, month, day, hour, 
                  " >> ", control.file, sep = "")
    cat(line, file = script.file, sep="\n")
    
    line <- paste(hy.split.exec.dir, control.file.extension, sep=" ")
    cat(line, file = script.file, sep="\n")
    
    # close the file connection
    close(script.file)
    
    # run the file
    if(OS == "unix"){
      system(paste0("sh ", script.name))
    } else
    {
      system(paste0(script.name))
    }
    
    # create another control file
    control.file.number <- control.file.number + 1
  
  }
  
  # combine files and make data frame
  traj <- ReadFiles(process.working.dir, ID, dates.and.times, tz)
  
  # check if add new column was required
  if (add.new.column == T){
    if( !missing(new.column.name) & !missing(new.column.value) ){
      traj[new.column.name] <- new.column.value
    } else {
      stop("Parameters 'new.column.name' and 'new.column.value' are not defined.")
    }
  }
  
  # if the output [out] parameter is not specified
  # it will not save the results in the local file system
  if( !missing(out) ) {
    ## write R object to file
    file.name <- paste(out, name, Year, ".RData", sep = "")
    save(traj, file = file.name)
  }
  
  # sets the working directory back in order to delete the process folders
  setwd(hy.split.wd)

  # remove existing "tdump" files 
  if(clean.files == T){
    unlink(folder.name, recursive = TRUE)
  }
  
  traj
}
