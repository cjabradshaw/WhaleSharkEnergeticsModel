##################################
## whale shark energetics model ##
## Corey Bradshaw 13.10.2022    ##
##################################

###################################################################################################################
## accompanies paper:                                                                                            ##
## BARRY, C, C LEGASPI, TM CLARKE, G ARAUJO, CJA BRADSHAW, AC GLEISS, L MEYER, A PONZO, C HUVENEERS. In review.  ##
## A new approach to evaluate the energetic cost of whale shark tourism. Biological Conservation                 ##
###################################################################################################################

# fixed deterministic parameters
tmpR <- 25 # temperature at routine (ºC)
tmpP <- 30 # temperature at provisioning (ºC)
tmpCoef <- 2.64 # temperature coefficient
RMR2SMR <- 1.459854 # RMR/SMR ratio

# deterministic parameters with uncertainties
actRmn <- 0.01294 # routine activity
actRsd <- 0.001045037
actPmn <- 0.02453 # provisioning activity
actPsd <- 0.005184831
EdensPMmn <- 1.357 # energy density of provisioned meal (kj/g wet weight) (Motta, et al. 2010)
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
# 12.7 ± 4.3 SD individual whale sharks seen in survey area daily,
# with max presence 26 individuals (Aug 10 2013) (Araujo, et al. 2014)
Nws.daily.mn <- 12.7
Nws.daily.sd <- 4.3

# duration of tourism operation (hours)
tour.dur.min <- 4
tour.dur.max <- 6

# sea-surface temperatures
setwd("~/.../data/")
SSTdat <- read.csv("SST.csv", header=T)

# food provision vector (0-400 kg), in 10 kg increments
prov.vec <- seq(0,400,10)


########################
## stochastic run 1:  ##
## number of sharks   ##
## from distribution  ##
########################

iter <- 10000 # number of iterations per provision increment

# cycle through provisioning vector
prob.needs.met <- rep(NA,length(prov.vec)) # storage vector
for (p in 1:length(prov.vec)) {

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
    
    # BIOMASS EQUIVALENT (g FISH) PER HOUR REQUIRED TO BREAK EVEN
    Beqh.vec <- (Eeqh.vec/EdensPMday)/Ewastage 
    
    # MULTIPLY BIOMASS EQUIVALENT BY NUMBER OF HOURS OF OPERATION
    opDAY <- runif(1, min=tour.dur.min, max=tour.dur.max)
    Beq.vec <- Beqh.vec*opDAY
    
    # TOTAL AMOUNT OF FISH NEEDED TO BREAK EVEN ACROSS ALL SHARKS THIS DAY (kg)
    BeqTOT <- sum(Beq.vec, na.rm=T)/1000
    
    # DID AMOUNT OF FISH ACTUALLY SUPPLIED PER DAY MEET THE MINIMUM REQUIREMENT?
    needs.met[i] <- ifelse(BeqTOT <= prov.vec[p], 1, 0)
    
  } # end i
  
  prob.needs.met[p] <- sum(needs.met)/length(na.omit(needs.met))
  print(paste("food provided/day = ", prov.vec[p], " (kg)", sep=""))
  
} # end p

plot(prov.vec, prob.needs.met,type="l", xlab="food provisioned/day (kg)", ylab="Pr(needs met)")
abline(h=0.999, lty=2)
abline(v=prov.vec[min(which(prob.needs.met >= 0.999))], lty=2)
prov.vec[min(which(prob.needs.met >= 0.999))] # mass (kg) of food where Pr >= 0.999 that whale sharks' energetic needs are met

needsMet.dat <- data.frame(prov.vec, prob.needs.met)
write.table(needsMet.dat,file="prNeedsMet.csv",sep=",",row.names=T,col.names=T) # save x,y file



########################
## stochastic run 2:  ##
## incrementing       ##
## number of sharks   ##
########################

iter <- 10000 # number of iterations per provision increment

# cycle through number of sharks
nshark.vec <- seq(1,30,1)
pr.mat <- matrix(data=NA, nrow=length(nshark.vec), ncol=length(prov.vec)) # storage matrix

for (s in 1:length(nshark.vec)) {
  
  # cycle through provisioning vector
  for (p in 1:length(prov.vec)) {
    
    needs.met <- rep(NA,iter) # storage vector
    for (i in 1:iter) {

      # GENERATE LENGTH DISTRIBUTION OF NUMBER OF SHARKS
      lenDISTday.it <- rnorm(nshark.vec[s], mean=WSLmn, sd=WSLsd)
      
      # TRANSLATE LENGTHS TO MASSES (g)
      massDISTday.it <- 1000*12.1*lenDISTday.it^WSLMexp
      
      # SAMPLE A TEMPERATURE FOR THIS DAY
      tmpDAY <- sample(SSTdat$monthSSTmn,1,replace=T)
      
      # APPLY AN ACTIVITY TO EACH SHARK
      actRindDAY <- rnorm(nshark.vec[s], mean=actRmn, sd=actRsd) # routine
      actPindDAY <- rnorm(nshark.vec[s], mean=actPmn, sd=actPsd) # provisioning
      
      # SMR15 FOR EACH SHARK
      # SMR scaling expoonent for each shark
      SMRexpIND <- rnorm(nshark.vec[s], mean=SMRexpmn, sd=SMRexpsd)
      
      SMR15indDAY <- rep(NA,nshark.vec[s])
      for (w in 1:nshark.vec[s]) {
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
      
      # BIOMASS EQUIVALENT (g FISH) PER HOUR REQUIRED TO BREAK EVEN
      Beqh.vec <- (Eeqh.vec/EdensPMday)/Ewastage 
      
      # MULTIPLY BIOMASS EQUIVALENT BY NUMBER OF HOURS OF OPERATION
      opDAY <- runif(1, min=tour.dur.min, max=tour.dur.max)
      Beq.vec <- Beqh.vec*opDAY
      
      # TOTAL AMOUNT OF FISH NEEDED TO BREAK EVEN ACROSS ALL SHARKS THIS DAY (kg)
      BeqTOT <- sum(Beq.vec, na.rm=T)/1000
      
      # DID AMOUNT OF FISH ACTUALLY SUPPLIED PER DAY MEET THE MINIMUM REQUIREMENT?
      needs.met[i] <- ifelse(BeqTOT <= prov.vec[p], 1, 0)
      
    } # end i
    
    pr.mat[s,p] <- sum(needs.met)/length(na.omit(needs.met))
    #print(paste("food provided/day = ", prov.vec[p], " (kg)", sep=""))
    
  } # end p
  
  print("##################################")
  print(paste("number of sharks = ", nshark.vec[s], sep=""))
  print("##################################")
  
} # end s

heatmap(pr.mat, Rowv=NA, Colv=NA, labRow=nshark.vec, labCol=prov.vec, xlab="food provided/day (kg)", ylab="# sharks present")

pr.out <- as.data.frame(pr.mat)
colnames(pr.out) <- prov.vec
rownames(pr.out) <- nshark.vec
write.table(pr.out,file="prout.csv",sep=",",row.names=T,col.names=T) # save matrix of probabilities (rows = no. sharks; columns = food-provision increment)


