# lavPredict() contains a collection of `predict' methods
# the unifying theme is that they all rely on the factor scores
#
# lv: factor scores
# ov: predict linear part of y_i
# fy: conditional density of y (given lv's and exo) (under independence!)
#
# first version: YR 11 June 2013

# overload standard R function `predict'
setMethod("predict", "lavaan",
function(object, newdata=NULL) {
    lavPredict(object = object, newdata = newdata, type="lv", method="EBM")
})

# main function
lavPredict <- function(object, type="lv", newdata=NULL, method="EBM",
                       se.fit=FALSE, label=TRUE) {

    stopifnot(inherits(object, "lavaan"))
    type <- tolower(type)
    if(type %in% c("latent", "lv", "factor", "factor.score", "factorscore"))
        type <- "lv"
    if(type %in% c("ov","yhat")) 
        type <- "yhat"

    # need full data set supplied
    if(is.null(newdata)) {
        # use internal copy:
        if(is.null(object@Data@X[[1]])) {
            stop("no local copy of data; FIXME!")
        } else {
            data.obs <- object@Data@X
        }
        eXo <- object@Data@eXo
    } else {
        OV <- object@Data@ov
        newData <- lavData(data        = newdata,
                           group       = object@Data@group,
                           group.label = object@Data@group.label,
                           ov.names    = object@Data@ov.names,
                           ordered     = OV$name[ OV$type == "ordered" ],
                           ov.names.x  = object@Data@ov.names.x,
                           std.ov      = object@Data@std.ov,
                           missing     = object@Data@missing,
                           # warn      = FALSE,
                           allow.single.case = TRUE)
        data.obs <- newData@X
        eXo <- newData@eXo
    }

    # normal case?
    NORMAL <- all(object@Data@ov$type == "numeric")

    if(type == "lv") {
        if(NORMAL && method == "EBM") {
            out <- lav_predict_eta_normal(object = object, 
                data.obs = data.obs, eXo = eXo, label = label,
                remove.dummy.lv = TRUE)
        } else {
        out <- lav_predict_eta_ebm(object = object, 
                data.obs = data.obs, eXo = eXo, label = label)
        }
    } else if(type == "yhat") {
        out <- lav_predict_yhat(object = object, data.obs = data.obs,
                              eXo = eXo, method = method, label = label)
    } else if(type == "fy") {
        out <- lav_predict_fy(object = object, data.obs = data.obs,
                              eXo = eXo, label = label)
    } else {
        stop("lavaan ERROR: type must be one of: lv mu fy")
    }

    # lavaan.matrix
    out <- lapply(out, "class<-", c("lavaan.matrix", "matrix"))

    if(object@Data@ngroups == 1L) {
        out <- out[[1L]]
    } else {
        out
    }

    out
}


## factor scores - EBM
lav_predict_eta_ebm <- function(object = NULL, data.obs = NULL, 
                                eXo = NULL, label = FALSE) {

    if(is.null(data.obs)) {
        data.obs <- object@Data@X
    }
    if(is.null(eXo)) {
        eXo <- object@Data@eXo
    }

    G <- object@Data@ngroups
    nmat <- object@Model@nmat
    FS <- vector("list", length=G)
    VETA <- computeVETA(object=object@Model, samplestats=object@SampleStats)
    EETAx <- computeEETAx(object=object@Model, eXo=eXo, nobs=object@Data@nobs)
    TH <- computeTH(object@Model)
    th.idx <- object@Model@th.idx

    f.eta.i <- function(x, y.i, x.i, mu.i, g) {
        # conditional density of y, given eta.i(=x)
        log.fy <- lav_predict_fy_eta.i(object = object, y.i = y.i, x.i = x.i,
                                       eta.i = x, group = g, 
                                       TH = TH[[g]], th.idx = th.idx[[g]],
                                       log = TRUE)
        tmp <- as.numeric(0.5 * t(x - mu.i) %*% VETA.inv.g %*% (x - mu.i))
        out <- tmp - sum(log.fy)
        #print(out)
        out
    }

    for(g in 1:G) {
        nfac <- length(vnames(object@ParTable, type="lv", group=g))
        FS[[g]] <- matrix(0, nrow(data.obs[[g]]), nfac)
        if(nfac == 0L) next

        VETA.inv.g <- solve(VETA[[g]])
        # if no eXo, only one mu.i per group
        if(is.null(eXo[[g]])) {
            mu.i <- as.numeric(EETAx[[g]])
            x.i <- NULL
        }

        # casewise for now
        N <- nrow(data.obs[[g]])
        for(i in 1:N) {
            if(!is.null(eXo[[g]])) {
                mu.i <- EETAx[[g]][i,]
                 x.i <- eXo[[g]][i,]
            }
            y.i <- data.obs[[g]][i,]
            
            # find best values for eta.i
            out <- nlminb(start=numeric(nfac), objective=f.eta.i,
                            gradient=NULL, # for now
                            y.i=y.i, x.i=x.i, mu.i=mu.i, g=g)
            if(out$convergence == 0L) {
                eta.i <- out$par
            } else {
                eta.i <- rep(as.numeric(NA), nfac)
            }

            FS[[g]][i,] <- eta.i
        }

        if(label) {
            colnames(FS[[g]]) <- vnames(object@ParTable, type="lv", group=g)
        }

    }

    FS
}

## factor scores - normal case
lav_predict_eta_normal <- function(object = NULL, data.obs = NULL, 
                                   eXo = NULL, label = FALSE,
                                   remove.dummy.lv = FALSE) {

    if(is.null(data.obs)) {
        data.obs <- object@Data@X
    }
    if(is.null(eXo)) {
        eXo <- object@Data@eXo
    }

    G <- object@Data@ngroups
    nmat <- object@Model@nmat
    FS <- vector("list", length=G)
   
    Sigma.hat <- computeSigmaHat(object@Model)
    Sigma.hat.inv <- lapply(Sigma.hat, solve)
    VETA <- computeVETA(object@Model, samplestats=object@SampleStats)
    EETA <- computeEETA(object@Model, samplestats=object@SampleStats)
    EY <- computeEY(object@Model, samplestats=object@SampleStats)
    LAMBDA <- computeLAMBDA(object@Model, remove.dummy.lv=FALSE)
     
    for(g in 1:G) {
        nfac <- ncol(VETA[[g]])
        if(nfac == 0L) {
            FS[[g]] <- matrix(0, object@Data@nobs[[g]], nfac)
            next
        }

        # use the classic 'regression' method
        # for the linear/continuous case, this is equivalent to both
        # EB and EBM

        # factor score coefficient matrix 'C'
        FSC = VETA[[g]] %*% t(LAMBDA[[g]]) %*% Sigma.hat.inv[[g]]

        RES <- sweep(data.obs[[g]], 2, STATS=EY[[g]], FUN="-")
        FS.g <- sweep(RES %*% t(FSC), 2, STATS=EETA[[g]], FUN="+")

        if(label) {
            lambda.idx <- which(names(object@Model@GLIST) == "lambda")[g]
            colnames(FS.g) <- object@Model@dimNames[[lambda.idx]][[2]]
        }

        if(remove.dummy.lv) {
            # remove dummy latent variables
            lv.idx <- c(object@Model@ov.y.dummy.lv.idx[[g]],
                        object@Model@ov.x.dummy.lv.idx[[g]])
            if(length(lv.idx) > 0L) {
                FS.g <- FS.g[, -lv.idx, drop=FALSE]
            }
        }

        FS[[g]] <- FS.g

    }

    FS
}


# predicted value for response y*_i, conditional on the predicted latent
# variable scores
# for all y*_i -> return [nobs x nvar] matrix per group
lav_predict_yhat <- function(object = NULL, data.obs = NULL, eXo = NULL,
                             method = "EBM", label = FALSE) {

    # measurement part
    # y*_i = nu + lambda eta_i + K x_i + epsilon_i
    # 
    # where eta_i = predict(fit) = factor scores

    if(is.null(data.obs)) {
        data.obs <- object@Data@X
    }
    if(is.null(eXo)) {
        eXo <- object@Data@eXo
    }
    G <- object@Data@ngroups
    nmat <- object@Model@nmat
    YHAT <- vector("list", length=G)

    # EETA only needed if meanstructure=FALSE
    EETA <- computeEETA(object@Model, samplestats=object@SampleStats)

    # normal case?
    NORMAL <- all(object@Data@ov$type == "numeric")

    # we need the factor scores (per groups)
    if(NORMAL && method == "EBM") {
        ETA <- lav_predict_eta_normal(object = object,
            data.obs = data.obs, eXo = eXo, label = label,
            remove.dummy.lv=TRUE)
    } else if(method == "EBM") {
        ETA <- lav_predict_eta_ebm(object = object,
            data.obs = data.obs, eXo = eXo, label = label,
            remove.dummy.lv=TRUE)
    } else {
        stop("lavaan ERROR: method ", method, " not (yet) supported of factor score prediction")
    }

    for(g in 1:G) {
        mm.in.group <- 1:nmat[g] + cumsum(c(0,nmat))[g]
        MLIST <- object@Model@GLIST[ mm.in.group ]
        DELTA <- MLIST$delta

        lv.dummy.idx <- c(object@Model@ov.y.dummy.lv.idx[[g]],
                          object@Model@ov.x.dummy.lv.idx[[g]])
        ov.dummy.idx <- c(object@Model@ov.y.dummy.ov.idx[[g]],
                          object@Model@ov.x.dummy.ov.idx[[g]])

        # exogenous variables?
        if(is.null(eXo[[g]])) {
            nexo <- 0L
        } else {
            nexo <- ncol(eXo[[g]])
        }
        nvar <- nrow(MLIST$lambda)

        # fix NU
        NU <- MLIST$nu
        if(!is.null(NU)) {
            if(length(lv.dummy.idx) > 0L) {
                NU[ov.dummy.idx, 1L] <- MLIST$alpha[lv.dummy.idx, 1L]
            }
        } else {
            # if nexo == 0L, fill in unrestricted mean
            NU <- object@SampleStats@mean[[g]]
            # if nexo > 0, substract lambda %*% EETA
            if(nexo > 0L) {
                ov.idx <- which(object@pta$vnames$ov[[1]] %in% 
                                object@pta$vnames$ov.nox[[1]])
                LAMBDA.X <- MLIST$lambda
                if(length(object@Model@ov.y.dummy.ov.idx[[g]]) > 0L) {
                    LAMBDA.X[object@Model@ov.y.dummy.ov.idx[[g]],] <-
                        MLIST$beta[object@Model@ov.y.dummy.lv.idx[[g]],
                                   ,drop=FALSE]
                }
                # we need LAMBDA with the dummy variables
                NU[ov.idx] <- (NU - LAMBDA.X %*% EETA[[g]])[ov.idx]
            }
        }

        # fix LAMBDA
        LAMBDA <- MLIST$lambda
        if(length(lv.dummy.idx) > 0L) {
            LAMBDA <- LAMBDA[, -lv.dummy.idx, drop=FALSE]
            nfac <- ncol(LAMBDA)
            LAMBDA[object@Model@ov.y.dummy.ov.idx[[g]],] <-
                MLIST$beta[object@Model@ov.y.dummy.lv.idx[[g]],
                           1:nfac, drop=FALSE]
        }

        # compute YHAT
        YHAT[[g]] <- sweep(ETA[[g]] %*% t(LAMBDA), MARGIN=2, NU, "+")

        # Kappa + eXo?
        # note: Kappa elements are either in Gamma or in Beta
        if(nexo > 0L) {
            KAPPA <- matrix(0, nvar, nexo)
            if(!is.null(MLIST$gamma)) {
                KAPPA[object@Model@ov.y.dummy.ov.idx[[g]],] <- 
                    MLIST$gamma[object@Model@ov.x.dummy.lv.idx[[g]],,drop=FALSE]
            } else if(length(object@Model@ov.x.dummy.ov.idx[[g]]) > 0L) {
                KAPPA[object@Model@ov.y.dummy.ov.idx[[g]],] <-
                    MLIST$beta[object@Model@ov.y.dummy.lv.idx[[g]],
                               object@Model@ov.x.dummy.lv.idx[[g]], drop=FALSE]
            }

            # add fixed part
            YHAT[[g]] <- YHAT[[g]] + (eXo[[g]] %*% t(KAPPA))

            # put back eXo
            if(length(object@Model@ov.x.dummy.ov.idx[[g]]) > 0L) {
                YHAT[[g]][, object@Model@ov.x.dummy.ov.idx[[g]]] <- eXo[[g]]
            }
        }

        # delta?
        if(!is.null(DELTA)) {
            YHAT[[g]] <- sweep(YHAT[[g]], MARGIN=2, DELTA, "*")
        }

        if(label) {
            colnames(YHAT[[g]]) <- vnames(object@ParTable, type="ov", group=g)
        }

    }
    
    YHAT
}

# expectation of the response, conditional on the latent variables
# for given values 'eta' of a single observation (i) (eta.i)
lav_predict_mu_eta.i <- function(object = NULL, eta.i = NULL, x.i = NULL, 
                                 group = 1L) {

    # measurement part
    # y*_i = nu + lambda eta_i + K x_i + epsilon_i
    # 
    # where eta_i = predict(fit) = factor scores

    g <- group
    nmat <- object@Model@nmat
    nvar <- object@Model@nvar[g]
    mm.in.group <- 1:nmat[g] + cumsum(c(0,nmat))[g]
    MLIST     <- object@Model@GLIST[ mm.in.group ]
        NU <- MLIST$nu
    LAMBDA <- MLIST$lambda
     GAMMA <- MLIST$gamma
     DELTA <- MLIST$delta

    # remove dummy's from LAMBDA
    r.idx <- object@Model@ov.dummy.row.idx[[g]]
    c.idx <- object@Model@ov.dummy.col.idx[[g]]
    if(!is.null(c.idx)) {
        LAMBDA <- LAMBDA[,-c.idx,drop=FALSE]
    }

    # nu? if not, set to sample means
    if( is.null(NU) ) {
        NU <- object@SampleStats@mean[[g]]
    }

    # measurement model
    MU <- as.numeric(NU + LAMBDA %*% eta.i)

    # K + eXo?
    # note: K elements are in Gamma
    if(!is.null(x.i) && !is.null(GAMMA)) {
        MU.x <- numeric(nvar)
        MU.x[r.idx] <- (GAMMA[c.idx,,drop=FALSE] %*% x.i)
        MU <- MU + MU.x
    }

    # Delta?
    if(!is.null(DELTA)) {
        MU <- DELTA * MU
    }
    
    MU
}

# conditional density y -- assuming independence!!
# f(y_i | eta_i, x_i)
lav_predict_fy <- function(object = NULL, data.obs = NULL,
                           label = FALSE) {

    if(is.null(data.obs)) {
        data.obs <- object@Data@X
    }
    G <- object@Data@ngroups
    nmat <- object@Model@nmat
    FY <- vector("list", length=G)

    # we need the MUs (per group)
    MU <- lav_predict_mu(object = object, data.obs = data.obs)

    # all normal?
    NORMAL <- all(object@Data@ov$type == "numeric")

    for(g in 1:G) {
        mm.in.group <- 1:nmat[g] + cumsum(c(0,nmat))[g]
        MLIST     <- object@Model@GLIST[ mm.in.group ]

        THETA <- MLIST$theta
        theta <- diag(THETA)

        if(NORMAL) {
            tmp <-  (data.obs[[g]] - MU[[g]])^2 
            tmp1 <- sweep(tmp, MARGIN=2, theta, "/")
            tmp2 <- exp( -0.5 * tmp1 )
            tmp3 <- sweep(tmp2, MARGIN=2, sqrt(2*pi*theta), "/")
            FY[[g]] <- tmp3
        } else {
            stop("not ready yet")
        }

        if(label) {
            colnames(FY[[g]]) <- vnames(object@ParTable, type="ov", group=g)
        }

    }

    FY
}

# conditional density y -- assuming independence!!
# f(y_i | eta_i, x_i)
# but for a single observation y_i (and x_i), for given values of eta_i
lav_predict_fy_eta.i <- function(object = NULL, y.i = NULL, x.i = NULL,
                                 eta.i = NULL, group = 1L, 
                                 TH = NULL, th.idx = NULL, log = TRUE) {

    g <- group
    nvar <- object@Model@nvar[g]
    nmat <- object@Model@nmat

    # we need the MU
    MU <- lav_predict_mu_eta.i(object = object, eta.i = eta.i, x.i = x.i,
                               group = group)

    # all normal?
    NORMAL <- all(object@Data@ov$type == "numeric")

    mm.in.group <- 1:nmat[g] + cumsum(c(0,nmat))[g]
    MLIST     <- object@Model@GLIST[ mm.in.group ]

    THETA <- MLIST$theta
    theta <- sqrt(diag(THETA))

    if(NORMAL) {
        FY <- dnorm(y.i, mean=MU, sd=theta, log = log)
    } else {
        FY <- numeric(nvar)
        for(v in seq_len(nvar)) {
            if(object@Data@ov$type[v] == "numeric") {
                ### FIXME!!! we can do all numeric vars at once!!
                FY[v] <- dnorm(y.i[v], mean=MU[v], sd=theta[v], log = log)
            } else if(object@Data@ov$type[v] == "ordered") {
                th.y <- TH[ th.idx == v ]; TH.Y <-  c(-Inf, th.y, Inf)
                k <- y.i[v]
                p1 <- pnorm( (TH.Y[ k + 1 ] - MU[v])/theta[v] )
                p2 <- pnorm( (TH.Y[ k     ] - MU[v])/theta[v] )
                prob <- (p1 - p2)
                if(log) {
                    FY[v] <- log(prob)
                } else {
                    FY[v] <- prob
                }
            } else {
                stop("lavaan ERROR: unknown type: ", 
                      object@Data@ov$type[v], " for variable", 
                      object@Data@ov$name[v])
            }
        }
    }

    FY
}
