#' @import Rook

#' @title Generate a Rook Server app from a pagoda2 object
#' @description Contains some code required to convert from the pagoda2 object to the
#' web object constructor. Advanced users may wish to use the PagodaWebApp
#' constructor directly
#' @param r pagoda2 object
#' @param dendrogramCelllGoups a named factor of cell groups, used to generate the main dendrogram
#' @param additionalMetadata a list of metadata other than depth, batch and cluster that are automatically added
#' @param geneSets a list of genesets to show
#' @param debug build debug app?
#' @return a Rook web app
#' @export make.p2.app
make.p2.app <- function(r, dendrogramCellGroups, additionalMetadata = list(), geneSets) {

                                        # dendrogramCellGroups is named factor of cells
                                        # that assigns cells to groups that will be the smallest
                                        # group that we can zoom in
                                        # We probably want this to be a partition of the actual displayed clusters
                                        # So that the user can zoom in a bit further than the cluster level



    # Build the metadata
    metadata <- list();
    if ( "depth" %in% names(r@.xData) ) {
        if ( !is.null(r@.xData$depth ) ) {
            levels  <- 20

            dpt <- log10(r@.xData$depth+0.00001)
            max <- max(dpt)
            min <- min(dpt)
            dptnorm <- floor((dpt - min) / (max - min) * levels) + 1
            metadata$depth <- list(
                data = dptnorm,
                palette = colorRampPalette(c('white','black'))(levels+1)
            )


        }
    }
    if ( "batch" %in% names(r@.xData) ) {
        if ( !is.null(r@.xData$batch)  ) {
            metadata$batch <- list(
                data = r$batch,
                palette = rainbow(n = length(levels(r$batch)))
            )
        }
    }
    metadata$clusters <- list(
            data = dendrogramCellGroups,
            palette = rainbow(n =  length(levels(dendrogramCellGroups)))
    )
    # Append the additional metadata
    for ( itemName in names(additionalMetadata)) {
        metadata[[itemName]] <- additionalMetadata[[itemName]]
    }


    # Make the app object
    p2w <- pagoda2WebApp$new(
        pagoda2obj = r,
        appName = "DefaultPagoda2Name",
        dendGroups = dendrogramCellGroups,
        verbose = 0,
        debug = TRUE,
        geneSets = geneSets,
        metadata = metadata)
}




#' @export show.app
show.app <- function(app, name, port, ip, browse = TRUE,  server = NULL) {
                                        # replace special characters
    name <- gsub("[^[:alnum:.]]", "_", name)

    if(is.null(server)) {
        server <- get.scde.server(port=port,ip=ip)
    }
    server$add(app = app, name = name)
    if(is.function(server$listenPort)) {
        url <- paste("http://", server$listenAddr, ":", server$listenPort(), server$appList[[name]]$path,"/index.html",sep='')
    } else {
        url <- paste("http://", server$listenAddr, ":", server$listenPort, server$appList[[name]]$path,"/index.html",sep='')
    }
    print(paste("app loaded at: ",url,sep=""))
    if(browse) {
        browseURL(url);
    }

    return(invisible(server))
}

                                        # get SCDE server from saved session
get.scde.server <- function(port,ip) {
    if(exists("___scde.server", envir = globalenv())) {
        server <- get("___scde.server", envir = globalenv())
    } else {
        require(Rook)
        server <- Rhttpd$new()
        assign("___scde.server", server, envir = globalenv())
        if(!missing(ip)) {
            if(missing(port)) {
                server$start(listen = ip)
            } else {
                server$start(listen = ip, port = port)
            }
        } else {
            if(missing(port)) {
                server$start()
            } else {
                server$start(port=port)
            }
        }
    }
    return(server)
}

# BH P-value adjustment with a log option
bh.adjust <- function(x, log = FALSE) {
    nai <- which(!is.na(x))
    ox <- x
    x<-x[nai]
    id <- order(x, decreasing = FALSE)
    if(log) {
        q <- x[id] + log(length(x)/seq_along(x))
    } else {
        q <- x[id]*length(x)/seq_along(x)
    }
    a <- rev(cummin(rev(q)))[order(id)]
    ox[nai]<-a
    ox
}

# returns enriched categories for a given gene list as compared with a given universe
# returns a list with over and under fields containing list of over and underrepresented terms
calculate.go.enrichment <- function(genelist, universe, pvalue.cutoff = 1e-3, mingenes = 3, env = go.env, subset = NULL, list.genes = FALSE, over.only = FALSE) {
    genelist <- unique(genelist)
    all.genes <- unique(ls(env))
    # determine sizes
    universe <- unique(c(universe, genelist))
    universe <- universe[universe != ""]
    genelist <- genelist[genelist != ""]
    ns <- length(intersect(genelist, all.genes))
    us <- length(intersect(universe, all.genes))
    #pv <- lapply(go.map, function(gl) { nwb <- length(intersect(universe, gl[[1]])) if(nwb<mingenes) { return(0.5)} else { p <- phyper(length(intersect(genelist, gl[[1]])), nwb, us-nwb, ns) return(ifelse(p > 0.5, 1.0-p, p)) }})

    # compile count vectors
    stab <- table(unlist(mget(as.character(genelist), env, ifnotfound = NA), recursive = TRUE))
    utab <- table(unlist(mget(as.character(universe), env, ifnotfound = NA), recursive = TRUE))
    if(!is.null(subset)) {
        stab <- stab[names(stab) %in% subset]
        utab <- utab[names(utab) %in% subset]
    }

    tabmap <- match(rownames(stab), rownames(utab))

    cv <- data.frame(cbind(utab, rep(0, length(utab))))
    names(cv) <- c("u", "s")
    cv$s[match(rownames(stab), rownames(utab))] <- as.vector(stab)
    cv <- na.omit(cv)
    cv <- cv[cv$u > mingenes, ]

    if(over.only) {
        lpr <- phyper(cv$s-1, cv$u, us-cv$u, ns, lower.tail = FALSE, log.p = TRUE)
    } else {
        pv <- phyper(cv$s, cv$u, us-cv$u, ns, lower.tail = FALSE)
        lpr <- ifelse(pv<0.5, phyper(cv$s-1, cv$u, us-cv$u, ns, lower.tail = FALSE, log.p = TRUE), phyper(cv$s+1, cv$u, us-cv$u, ns, lower.tail = TRUE, log.p = TRUE))
    }
    lpr <- phyper(cv$s-1, cv$u, us-cv$u, ns, lower.tail = FALSE, log.p = TRUE)
    lpra <- bh.adjust(lpr, log = TRUE)
    z <- qnorm(lpr, lower.tail = FALSE, log.p = TRUE)
    za <- qnorm(lpra, lower.tail = FALSE, log.p = TRUE)
    # correct for multiple hypothesis
    mg <- length(which(cv$u > mingenes))
    if(over.only) {
        if(pvalue.cutoff<1) {
            ovi <- which(lpra<= log(pvalue.cutoff))
            uvi <- c()
        } else {
            ovi <- which((lpr+mg)<= log(pvalue.cutoff))
            uvi <- c()
        }
    } else {
        if(pvalue.cutoff<1) {
            ovi <- which(pv<0.5 & lpra<= log(pvalue.cutoff))
            uvi <- which(pv > 0.5 & lpra<= log(pvalue.cutoff))
        } else {
            ovi <- which(pv<0.5 & (lpr+mg)<= log(pvalue.cutoff))
            uvi <- which(pv > 0.5 & (lpr+mg)<= log(pvalue.cutoff))
        }
    }
    ovi <- ovi[order(lpr[ovi])]
    uvi <- uvi[order(lpr[uvi])]

    #return(list(over = data.frame(t = rownames(cv)[ovi], o = cv$s[ovi], u = cv$u[ovi], p = pr[ovi]*mg), under = data.frame(t = rownames(cv)[uvi], o = cv$s[uvi], u = cv$u[uvi], p = pr[uvi]*mg)))
    if(list.genes) {
        x <- mget(as.character(genelist), env, ifnotfound = NA)
        df <- data.frame(id = rep(names(x), unlist(lapply(x, function(d) length(na.omit(d))))), go = na.omit(unlist(x)), stringsAsFactors = FALSE)
        ggl <- tapply(df$id, as.factor(df$go), I)
        ovg <- as.character(unlist(lapply(ggl[rownames(cv)[ovi]], paste, collapse = " ")))
        uvg <- as.character(unlist(lapply(ggl[rownames(cv)[uvi]], paste, collapse = " ")))
        return(list(over = data.frame(t = rownames(cv)[ovi], o = cv$s[ovi], u = cv$u[ovi], Za = za, fe = cv$s[ovi]/(ns*cv$u[ovi]/us), genes = ovg), under = data.frame(t = rownames(cv)[uvi], o = cv$s[uvi], u = cv$u[uvi], Za = za, fe = cv$s[uvi]/(ns*cv$u[uvi]/us), genes = uvg)))
    } else {
        return(list(over = data.frame(t = rownames(cv)[ovi], o = cv$s[ovi], u = cv$u[ovi], p.raw = exp(lpr[ovi]), fdr = exp(lpra)[ovi], Z = z[ovi], Za = za[ovi], fe = cv$s[ovi]/(ns*cv$u[ovi]/us), fer = cv$s[ovi]/(length(genelist)*cv$u[ovi]/length(universe))), under = data.frame(t = rownames(cv)[uvi], o = cv$s[uvi], u = cv$u[uvi], p.raw = exp(lpr[uvi]), fdr = exp(lpra)[uvi], Z = z[uvi], Za = za[uvi], fe = cv$s[uvi]/(ns*cv$u[uvi]/us))))
    }
}