##################################
## whale shark energetics model ##
## Corey Bradshaw 10.02.2023    ##
##################################

###################################################################################################################
## accompanies paper:                                                                                            ##
## BARRY, C, C LEGASPI, TM CLARKE, G ARAUJO, CJA BRADSHAW, AC GLEISS, L MEYER, C HUVENEERS. 2023.                ##
## Estimating the energetic cost of whale shark tourism. Biological Conservation 284: 110164                     ##
###################################################################################################################

# fixed deterministic parameters
tmpR <- 25 # temperature at routine (ºC)
tmpP <- 30 # temperature at provisioning (ºC)
tmpCoef <- 2.64 # temperature coefficient (Q10)
RMR2SMR <- 1.459854 # RMR/SMR ratio

# deterministic parameters with uncertainties
actRmn <- 0.01294 # routine activity
actRsd <- 0.001045037
actPmn <- 0.02453 # provisioning activity
actPsd <- 0.005184831
EdensPMmn <- 1.357 # energy density of provisioned meal (kJ/g wet weight) (Motta, et al. 2010)
EdensPMsd <- 0.084 # (Motta, et al. 2010)
SMRexpmn <- 0.8406 # SMR scaling exponent
SMRexpsd <- 0.0271

# length-mass relationship
WSLmn <- 5.5 # whale shark length (m)
WSLsd <- 1.3
WSLMexp <- 2.862 # mass-length exponent (Hsu et al. 2012)
WSmassCalc <- 1000*12.1*WSLmn^WSLMexp # calculated mass (g) (test with mean)

# deterministic (mean) calculations
SMR15int <- 1.1366 # SMR15 intercept
SMR15 <- exp(SMRexpmn*log(WSmassCalc)-SMR15int) # SMR at 15 ºC
SMRnp <- tmpCoef^(1/(10/(tmpR-15)))*SMR15 # SMR (non-provisioned) (mg O2 h-1)
MRnp <- SMRnp*RMR2SMR # MR- (non-provisioned) (mg O2 h-1)
O2np <- SMRnp*(RMR2SMR-1) # O2 for activity (non-provisioned) (mg O2 h-1)
O2p <- O2np/actRmn*actPmn # O2 for activity (provisioned) (mg O2 h-1)
SMRp <- tmpCoef^(1/(10/(tmpP-15)))*SMR15 # SMR (provisioned) (mg O2 h-1)
MRp <- O2p+SMRp # MR (provisioned) (mg O2 h-1)
dO2cons <- MRp - MRnp # Δ oxygen consumption/hour (mg O2 h-1)
Eeqh <- dO2cons/1000*13.6 # energy equivalent (kJ) per hour
Ewastage <- 0.73
Beqh <- (Eeqh/EdensPMmn)/Ewastage # biomass equivalent (g of fish) per hour

# number of whale sharks in area
# 14 ± 5.49 SD individual whale sharks seen in survey area daily
# Legaspi et al. 2020
Nws.daily.mn <- 14
Nws.daily.sd <- 5.49

# duration of tourism operation (hours)
tour.dur.min <- 4
tour.dur.max <- 6

# sea-surface temperatures
setwd("~/Documents/Papers/Fish/Sharks/Whale sharks/Energy")
SSTdat <- read.csv("SST.csv", header=T)


#################################
## global sensitivity analysis ##
#################################
library(doSNOW)
library(iterators)
library(snow)
library(foreach)
library(lhs)
library(data.table)

## parameter ranges to test
  # standard metabolic rate scaling exponent
  SMRexpUp <- 1.291; SMRexpLo <- 0.384 # model value = 0.8406 ± 0.0271
  # food energy density
  EdensPMup <- 1.609; EdensPMlo <- 1.105 # model value = 1.357 ± 0.084
  # number of whale sharks at site
  Nws.dailyUp <- 31; Nws.dailyLo <- 5 # model value = 12.7 ± 4.3
  # temperature coefficient (Q10)
  tmpCoefUp <- 3.48; tmpCoefLo <- 2.08 # model value = 2.64
  # routine activity
  actRup <- 0.015108298; actRlo <- 0.011600093 # model value = 0.01294 ± 0.001045037
  # provisioning activity
  actPup <- 0.032296; actPlo <- 0.0160242 # model value = 0.02453 ± 0.005184831

## Set up parallel processing (nproc is the number of processing cores to use)
nproc <- 6
cl.tmp = makeCluster(rep('localhost',nproc), type='SOCK')
registerDoSNOW(cl.tmp)
getDoParWorkers()
  
provisioned <- 100 # (at provision = x kg)
iter <- 10000

# set Latin hypercube resampling function
wsMR_sim <- function(input, dir.nm, rowNum) {
  
  ## assign all parameter values
  for (d in 1:ncol(input)) {assign(names(input)[d], input[,d])}
  
  # run model (at provision set above)

  needs.met <- rep(NA,iter) # storage vector
  for (i in 1:iter) {
    # GENERATE NUMBER OF SHARKS ON DAY
    nWSday.it <- round(rnorm(1, mean=Nws.daily.mn, sd=Nws.daily.sd),0)
    nWSday.it <- ifelse(nWSday.it < 0, 0, nWSday.it)
    
    # GENERATE LENGTH DISTRIBUTION OF THOSE SHARKS
    lenDISTday.it <- rnorm(nWSday.it, mean=WSLmn, sd=WSLsd)
    
    # TRANSLATE LENGTHS TO MASSES (g)
    massDISTday.it <- 1000*12.1*lenDISTday.it^WSLMexp
    
    # SAMPLE A TEMPERATURE FOR THIS DAY
    tmpDAY <- sample(SSTdat$monthSSTmn,1,replace=T)
    
    # APPLY AN ACTIVITY TO EACH SHARK
    actRindDAY <- rnorm(nWSday.it, mean=actRmn, sd=actRsd) # routine
    actPindDAY <- rnorm(nWSday.it, mean=actPmn, sd=actPsd) # provisioning
    
    # SMR15 FOR EACH SHARK
    # SMR scaling expoonent for each shark
    SMRexpIND <- rnorm(nWSday.it, mean=SMRexpmn, sd=SMRexpsd)
    
    SMR15indDAY <- rep(NA,nWSday.it)
    for (w in 1:nWSday.it) {
      SMR15indDAY[w] <- exp(SMRexpIND[w]*log(massDISTday.it[w])-SMR15int)  
    }
    
    # SMR NON-PROVISIONED
    SMRnp.vec <- tmpCoef^(1/(10/(tmpR-15)))*SMR15indDAY
    
    # MR NON-PROVISIONED
    MRnp.vec <- SMRnp.vec*RMR2SMR
    
    # O2 NON-PROVISIONED
    O2np.vec <- SMRnp.vec*(RMR2SMR-1) # O2 for activity (non-provisioned) (mg O2 h-1)
    
    # O2 FOR ACTIVITY (PROVISIONED)
    O2p.vec <- O2np.vec/actRindDAY*actPindDAY
    
    # SMR (PROVISIONED)
    SMRp.vec <- tmpCoef^(1/(10/(tmpDAY-15)))*SMR15indDAY
    
    # MR (PROVISIONED)
    MRp.vec <- O2p.vec + SMRp.vec 
    
    # Δ 02 CONSUMPTION/HOUR
    dO2cons.vec <- MRp.vec - MRnp.vec
    
    # # energy equivalent (kJ) per hour
    Eeqh.vec <- dO2cons.vec/1000*13.6 
    
    # ENERGY DENSITY OF FOOD PROVIDED THAT DAY
    EdensPMday <- rnorm(1,mean=EdensPMmn,sd=EdensPMsd)
    
    # BIOMASS EQUIVALENT (g SHRIMP) PER HOUR REQUIRED TO BREAK EVEN
    Beqh.vec <- (Eeqh.vec/EdensPMday)/Ewastage 
    
    # MULTIPLY BIOMASS EQUIVALENT BY NUMBER OF HOURS OF OPERATION
    opDAY <- runif(1, min=tour.dur.min, max=tour.dur.max)
    Beq.vec <- Beqh.vec*opDAY
    
    # TOTAL AMOUNT OF SHRIMP NEEDED TO BREAK EVEN ACROSS ALL SHARKS THIS DAY (kg)
    BeqTOT <- sum(Beq.vec, na.rm=T)/1000
    
    # DID AMOUNT OF SHRIMP ACTUALLY SUPPLIED PER DAY MEET THE MINIMUM REQUIREMENT?
    needs.met[i] <- ifelse(BeqTOT <= provisioned, 1, 0)
    
  } # end i
  
  pneeds.met <- sum(needs.met)/length(na.omit(needs.met))
  
  # save response
  input$prob.needs.met <- pneeds.met
  save.nm <- paste0('res',sprintf("%09.0f", rowNum))
  assign(save.nm, input)
  save(list=save.nm,file=paste(dir.nm,save.nm,sep='/'))
  
} # end function

## parameter ranges
ranges <- list()
ranges$SMRexpmn <- c(SMRexpLo, SMRexpUp)
ranges$EdensPMmn <- c(EdensPMlo, EdensPMup)
ranges$Nws.daily.mn <- c(Nws.dailyLo, Nws.dailyUp)
ranges$tmpCoef <- c(tmpCoefLo, tmpCoefUp)
ranges$actRmn <- c(actRlo, actRup)
ranges$actPmn <- c(actPlo, actPup)

## create hypercube
nSamples <- 1000
lh <- data.frame(randomLHS(n=nSamples, k=length(ranges)))
names(lh) <- names(ranges)

## convert parameters to required scale
for (j in 1:ncol(lh)) {
  par <- names(lh)[j]
  lh[,par] <- qunif(lh[,j], min=ranges[[par]][1], max=ranges[[par]][2]) ## continuous
}

## number of iterations for each parameter set
lh$iter <- 100

## folder for saving the results of each row
## we could just store in memory, but then if something breaks we will lose the lot
dir.nm <- 'gsa'
dir.create(dir.nm)

## run in parallel
res <- foreach(rowNum=1:nrow(lh),.verbose=F) %do% {wsMR_sim(input=lh[rowNum,],dir.nm=dir.nm,rowNum=rowNum)}

res.nms <- list.files('gsa')
res.list <- lapply(res.nms, function(x) {load(paste('gsa',x,sep='/')) ; print(x) ; return(eval(as.name(x)))})
dat <- rbindlist(res.list)
head(dat)
dim(dat)[1]
tail(dat)
sum(is.na(dat$prob.needs.met))
hist(dat$prob.needs.met)

#########
## BRT ##
#########
library(dismo)
library(gbm)

dat.nona <- data.frame(na.omit(dat[!is.infinite(rowSums(dat)),]))
dim(dat.nona)[1]

brt.fit <- gbm.step(dat.nona, gbm.x = attr(dat.nona, "names")[1:6], gbm.y = attr(dat.nona, "names")[8], family="gaussian", max.trees=100000, tolerance = 0.0001, learning.rate = 0.0001, bag.fraction=0.75, tree.complexity = 2)
summary(brt.fit)
dim(dat.nona)[1]
gbm.plot(brt.fit)
gbm.plot.fits(brt.fit)

CV.cor <- 100 * brt.fit$cv.statistics$correlation.mean
CV.cor.se <- 100 *brt.fit$cv.statistics$correlation.se
print(c(CV.cor, CV.cor.se))
