Fit <- function(partable=NULL, start, model, x=NULL, VCOV=NULL, TEST=NULL) {

    stopifnot(is.list(partable), length(partable$lhs) == length(start),
              class(model) == "Model")

    # extract information from 'x'
    iterations = attr(x, "iterations")
    converged  = attr(x, "converged")
    fx         = attr(x, "fx")
    fx.group   = attr(fx, "fx.group")
    #print(fx.group)
    control    = attr(x, "control")
    attributes(fx) <- NULL
    x.copy <- x # we are going to change it (remove attributes)
    attributes(x.copy) <- NULL
    est <- getModelParameters(model, type="user")

    # did we compute standard errors?
    se <- numeric( length(est) )
    if(!is.null(VCOV)) { 
        x.var <- diag(VCOV)
        # check for negative values (what to do: NA or 0.0?)
        x.var[x.var < 0] <- as.numeric(NA)
        x.se <- sqrt( x.var )
        GLIST <- x2GLIST(model, x=x.se, type="free")
        se <- getModelParameters(model, GLIST=GLIST, type="user", 
                                 extra=FALSE) # no def/cin/ceq entries!
        # fixed parameters -> se = 0.0
        se[ which(partable$unco == 0L) ] <- 0.0

        # defined parameters: 
        def.idx <- which(partable$op == ":=")
        if(length(def.idx) > 0L) {
            if(!is.null(attr(VCOV, "BOOT.COEF"))) {
                BOOT <- attr(VCOV, "BOOT.COEF")
                BOOT.def <- apply(BOOT, 1, model@def.function)
                if(length(def.idx) == 1L) {
                    BOOT.def <- as.matrix(BOOT.def)
                } else {
                    BOOT.def <- t(BOOT.def)
                }
                def.cov <- cov(BOOT.def )
            } else {
                # regular delta method
                JAC <- try(lavJacobianC(func = model@def.function, x = x),
                           silent=TRUE)
                if(inherits(JAC, "try-error")) { # eg. pnorm()
                    JAC <- lavJacobianD(func = model@def.function, x = x)
                }
                def.cov <- JAC %*% VCOV %*% t(JAC)
            }
            se[def.idx] <- sqrt(diag(def.cov))
        }
    }

    # did we compute test statistics
    if(is.null(TEST)) {
        test <- list()
    } else {
        test <- TEST
    }

    # for convenience: compute model-implied Sigma and Mu
    Sigma.hat <- computeSigmaHat(model)
       Mu.hat <-    computeMuHat(model)
    if(model@categorical) {
        TH <- computeTH(model)
    } else {
        TH <- list()
    }


    # if bootstrapped parameters, add attr to 'est'
    if(!is.null(attr(VCOV, "BOOT.COEF"))) {
        attr(est, "BOOT.COEF") <- attr(VCOV, "BOOT.COEF")
    }

    new("Fit",
        npar       = max(partable$free),
        x          = x.copy,
        start      = start,
        est        = est,
        se         = se,
        fx         = fx,
        fx.group   = fx.group,
        iterations = iterations,
        converged  = converged,
        control    = control,
        Sigma.hat  = Sigma.hat,
        Mu.hat     = Mu.hat,
        TH         = TH,
        test       = test
       )
}
