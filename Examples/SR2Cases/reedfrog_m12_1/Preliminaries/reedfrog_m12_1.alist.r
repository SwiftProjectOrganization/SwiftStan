alist(
	surv ~ dbinom( density , p ) ,
	logit(p) <- a_tank[tank] ,
	a_tank[tank] ~ dnorm( 0 , 5 )
)