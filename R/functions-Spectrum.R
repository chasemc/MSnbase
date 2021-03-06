
removePeaks_Spectrum <- function(spectrum, t = "min", msLevel.) {
    ## Just remove peaks if spectrum's MS level matched msLevel.
    if (!missing(msLevel.)) {
        if (!(msLevel(spectrum) %in% msLevel.))
            return(spectrum)
    }
    if (isEmpty(spectrum)) return(spectrum)
    if (t == "min")
        t <- min(intensity(spectrum)[intensity(spectrum)>0])
    if (!is.numeric(t))
        stop("'t' must either be 'min' or numeric.")
    if (is.na(centroided(spectrum))) {
        warning("Centroided undefined (NA): keeping spectrum as is.")
        return(spectrum)
    } else if (centroided(spectrum)) {
        ints <- utils.removePeaks_centroided(spectrum@intensity, t)
    } else {
        ints <- utils.removePeaks(spectrum@intensity, t)
    }
    spectrum@intensity <- ints
    spectrum@tic <- sum(ints)
    return(spectrum)
}


clean_Spectrum <- function(spectrum, all, updatePeaksCount = TRUE, msLevel.) {
    ## Just clean the spectrum if its MS level matched msLevel.
    if (!missing(msLevel.)) {
        if (!(msLevel(spectrum) %in% msLevel.))
            return(spectrum)
    }
  keep <- utils.clean(spectrum@intensity, all)
  spectrum@intensity <- spectrum@intensity[keep]
  spectrum@mz <- spectrum@mz[keep]
  spectrum@peaksCount <- length(spectrum@intensity)
  return(spectrum)
}

quantify_Spectrum <- function(spectrum, method,
                              reporters, strict) {
    ## Parameters:
    ##  spectrum: object of class Spectrum
    ##  method: methods for how to quantify the peaks
    ##  reporters: object of class ReporterIons
    ##  strict: use full width of peaks or a limited range around apex
    ## Return value:
    ##  a names list of length 2 with
    ##   peakQuant: named numeric of length length(reporters)
    ##   curveStats: a length(reporters) x 7 data frame
    lrep <- length(reporters)
    peakQuant <- vector("numeric", lrep)
    names(peakQuant) <- reporterNames(reporters)
    curveStats <- matrix(NA, nrow = lrep, ncol = 7)
    for (i in 1:lrep) {
        ## Curve statistics
        dfr <- curveData(spectrum, reporters[i])
        ##  dfr:     mz int
        ##  1  114.1023   0
        ##  2  114.1063   2
        ##  3  114.1102   3
        ##  4  114.1142   4
        ##  ...
        if (strict) {
            lowerMz <- round(mz(reporters[i]) - width(reporters[i]),3)
            upperMz <- round(mz(reporters[i]) + width(reporters[i]),3)
            selMz <- (dfr$mz >= lowerMz) & (dfr$mz <= upperMz)
            dfr <- dfr[selMz,]
            dfr <- rbind(c(min(dfr$mz),0),
                         dfr,
                         c(max(dfr$mz),0))
        }
        maxInt <- max(dfr$int)
        nMaxInt <- sum(dfr$int == maxInt)
        baseLength <- nrow(dfr)
        if (strict)
            baseLength <- baseLength-2
        mzRange <- range(dfr$mz)
        precMz <- precursorMz(spectrum)
        if (length(precMz) != 1)
            precMz <- NA
        curveStats[i, ] <- c(maxInt,nMaxInt,baseLength,
                             mzRange,
                             reporters[i]@mz,precMz)
        ## Quantification
        if (method == "trapezoidation") {
            if (nrow(dfr) == 1) {
                if (!is.na(dfr$int))
                    warning(paste("Found only one mz value for precursor ",
                                  precursorMz(spectrum), " and reporter ",
                                  reporterNames(reporters[i]), ".\n",
                                  "  If your data is centroided, quantify with 'max'.",
                                  sep = ""))
            }
            ## Quantify reporter ions calculating the area
            ## under the curve by trapezoidation
            n <- nrow(dfr)
            ## - original code -
            ## x <- vector(mode = "numeric", length = n)
            ## for (j in 1:n) {
            ##     k <- (j%%n) + 1
            ##     x[j] <- dfr$mz[j] * dfr$int[k] - dfr$mz[k] * dfr$int[j]
            ## }
            ## peakQuant[i] <- abs(sum(x)/2)
            ## - updated -
            peakQuant[i] <- 0.5 * sum((dfr$mz[2:n] - dfr$mz[1:(n-1)]) *
                                      (dfr$int[2:n] + dfr$int[1:(n-1)]))
            ## area using zoo's rollmean, but seems slightly slower
            ## peakQuant[i] <- abs(sum(diff(dfr$int)*rollmean(dfr$mz,2)))
        } else if (method == "sum") {
            ## Quantify reporter ions using sum of data points of the peak
            peakQuant[i] <- sum(dfr$int)
        }  else if (method == "max") {
            ## Quantify reporter ions using max peak intensity
            peakQuant[i] <- max(dfr$int)
        }
    }
    colnames(curveStats) <- c("maxInt", "nMaxInt", "baseLength",
                              "lowerMz", "upperMz", "reporter",
                              "precursor")
    ## curveStats <- as.data.frame(curveStats)
    return(list(peakQuant = peakQuant,
                curveStats = curveStats))
}


curveStats_Spectrum <- function(spectrum,reporters) {
  curveStats <- c()
  for (i in 1:length(reporters)) {
    dfr <- curveData(spectrum,reporters[i])
    maxInt <- max(dfr$int)
    nMaxInt <- sum(dfr$int==maxInt)
    baseLength <- nrow(dfr)
    mzRange <- range(dfr$mz)
    curveStats <- rbind(curveStats,
                        c(maxInt,nMaxInt,baseLength,
                          mzRange,
                          reporters[i]@mz,precursorMz(spectrum)))
  }
  colnames(curveStats) <- c("maxInt","nMaxInt","baseLength",
                            "lowerMz","upperMz",
                            "reporter","precursor")
  return(as.data.frame(curveStats))
}

curveData <- function(spectrum, reporter) {
  ## Returns a data frame with mz and intensity
  ## values (as columns) for all the points (rows)
  ## in the reporter spectrum. The base of the
  ## curve is extracted by getCurveWidth
  ## Paramters:
  ##  spectrum: object of class Spectrum
  ##  reporter: object of class ReporterIons of length 1
  ## Return value:
  ##  a data frame
  ##           mz int
  ## 1  114.1023   0
  ## 2  114.1063   2
  ## 3  114.1102   3
  ## 4  114.1142   4
  ## ...
  if (length(reporter) != 1) {
    warning("[curveData] Only returning data for first reporter ion")
    reporter <- reporter[1]
  }
  bp <- getCurveWidth(spectrum, reporter)
  if (any(is.na(bp))) {
    return(data.frame(mz = reporter@mz, int = NA))
  } else {
    int <- intensity(spectrum)[bp$lwr[1]:bp$upr[1]]
    mz <- mz(spectrum)[bp$lwr[1]:bp$upr[1]]
    return(data.frame(cbind(mz, int)))
  }
}

getCurveWidth <- function(spectrum, reporters) {
  ## This function returns curve base indices
  ## from a spectrum object for all the reporter ions
  ## in the reporter object
  ## CHANGED IN VERSION 1.1.2
  ## NOT ANYMORE Warnings: the function returns warnings if the
  ## NOT ANYMORE  mz[indeces] range outside of the original window
  ## NOT ANYMORE  reporter in the reporters object
  ## Parameters:
  ##  spectrum: object of class Spectrum
  ##  reporters: object of class ReporterIons
  ## Return value:
  ##  list of length 2
  ##   - list$lwr of length(reporters) lower indices
  ##   - list$upr of length(reporters) upper indices
  m <- reporters@mz
  lwr <- m - reporters@width
  upr <- m + reporters@width
  mz <- spectrum@mz
  int <- spectrum@intensity
  ## if first/last int != 0, this function crashes in the while
  ## (ylwr!=0)/(yupr!=0) loops. Adding leading/ending data points to
  ## avoid this. Return values xlwr and xupr get updated accordingly
  ## [*].
  mz <- c(0, mz, 0)
  int <- c(0, int, 0)
  ## x... vectors of _indices_ of mz values
  ## y... intensity values
  xlwr <- xupr<- c()
  for (i in 1:length(m)) {
    region <- (mz > lwr[i] & mz < upr[i])
    if (sum(region, na.rm = TRUE) == 0) {
        ## warning("[getCurveData] No data for for precursor ",
        ##         spectrum@precursorMz, " reporter ", m[i])
      xlwr[i] <- xupr[i] <- NA
    } else {
      ymax <- max(int[region])
      xmax <- which((int %in% ymax) & region)
      xlwr[i] <- min(xmax) ## if several max peaks
      xupr[i] <- max(xmax) ## if several max peaks
      if (!is.na(centroided(spectrum)) & !centroided(spectrum)) {
        ylwr <- yupr <- ymax
        while (ylwr != 0) {
          xlwr[i] <- xlwr[i] - 1
          ylwr <- int[xlwr[i]]
        }
        ## if (mz[xlwr[i]] < lwr[i])
        ##   warning("Peak base for precursor ",spectrum@precursorMz,
        ##           " reporter ", m[i],": ", mz[xlwr[i]], " < ",
        ##           m[i], "-", reporters@width, sep = "")
        while (yupr != 0) {
          xupr[i] <- xupr[i] + 1
          yupr <- int[xupr[i]]
        }
        ## if (mz[xupr[i]]>upr[i])
        ##   warning("Peak base for precursor ",spectrum@precursorMz,
        ##           " reporter ",m[i],": ",mz[xlwr[i]]," > ",m[i],"+",
        ##           reporters@width,sep="")
      }
      ##
      ## --|--|--|--|--|--|--
      ##      1  2  3  4      indeces before c(0,mz,0)
      ##   1  2  3  4  5  6   indeces after  c(0,mz,0)
      ## lower index: if x_after > 1 x <- x -1 (else x <- x_after)
      ## upper index: always decrement by 1
      ##              if we have reached the last index (the 0), decrement by 2
      ##
      ## Updating xlwr, unless we reached the artificial leading 0
      if (xlwr[i] > 1)
        xlwr[i] <- xlwr[i] - 1
      ## Always updating xupr [*]
      if (xupr[i] == length(mz))
        xupr[i] <- xupr[i] - 2
      xupr[i] <- xupr[i] - 1
    }
  }
  return(list(lwr = xlwr, upr = xupr))
}

trimMz_Spectrum <- function(x, mzlim, msLevel., updatePeaksCount = TRUE) {
    ## If msLevel. not missing, perform the trimming only if the msLevel
    ## of the spectrum matches (any of) the specified msLevels.
    if (!missing(msLevel.)) {
        if (!(msLevel(x) %in% msLevel.))
            return(x)
    }
    mzmin <- min(mzlim)
    mzmax <- max(mzlim)
    sel <- (x@mz >= mzmin) & (x@mz <= mzmax)
    if (sum(sel) == 0) {
        msg <- paste0("No data points between ", mzmin,
                      " and ", mzmax,
                      " for spectrum with acquisition number ",
                      acquisitionNum(x),
                      ". Returning empty spectrum.")
        warning(paste(strwrap(msg), collapse = "\n"))
        x@mz <- x@intensity <- numeric()
        x@tic <- integer()
        x@peaksCount <- 0L
        return(x)
    }
    x@mz <- x@mz[sel]
    x@intensity <- x@intensity[sel]
    if (updatePeaksCount)
        x@peaksCount <- as.integer(length(x@intensity))
    return(x)
}

normalise_Spectrum <- function(object, method, value) {
  ints <- intensity(object)
  switch(method,
         max = div <- max(ints),
         sum = div <- sum(ints),
         value = div <- value)
  normInts <- ints / div
  object@intensity <- normInts
  if (validObject(object))
    return(object)
}

breaks_Spectrum <- function(object, binSize = 1L,
                            breaks = seq(floor(min(mz(object))),
                                     ceiling(max(mz(object))),
                            by = binSize)) {
  ## assumming that mz and breaks are sorted
  if (mz(object)[peaksCount(object)] >= breaks[length(breaks)]) {
    breaks <- c(breaks, ceiling(mz(object)[peaksCount(object)] + mean(diff(breaks))))
  }
  breaks
}

breaks_Spectra <- function(object1, object2, binSize = 1L,
                           breaks = seq(floor(min(c(mz(object1), mz(object2)))),
                                        ceiling(max(c(mz(object1), mz(object2)))),
                                        by = binSize)) {
  sort(unique(c(breaks_Spectrum(object1, binSize = binSize, breaks = breaks),
                breaks_Spectrum(object2, binSize = binSize, breaks = breaks))))
}

bin_Spectrum <- function(object, binSize = 1L,
                         breaks = seq(floor(min(mz(object))),
                                      ceiling(max(mz(object))),
                                      by = binSize),
                         fun = sum,
                         msLevel.) {
  ## If msLevel. not missing, perform the trimming only if the msLevel
  ## of the spectrum matches (any of) the specified msLevels.
  if (!missing(msLevel.)) {
      if (!(msLevel(object) %in% msLevel.))
          return(object)
  }
  fun <- match.fun(fun)

  breaks <- breaks_Spectrum(object, binSize = binSize, breaks = breaks)
  nb <- length(breaks)

  idx <- findInterval(mz(object), breaks)
  idx[which(idx < 1L)] <- 1L
  idx[which(idx >= nb)] <- nb

  mz <- (breaks[-nb] + breaks[-1L]) / 2L
  intensity <- double(nb - 1L)

  intensity[unique(idx)] <- unlist(lapply(base::split(intensity(object), idx), fun))

  object@mz <- mz
  object@intensity <- intensity
  object@tic <- sum(intensity)
  object@peaksCount <- length(mz)
  if (validObject(object))
      return(object)
}

bin_Spectra <- function(object1, object2, binSize = 1L,
                        breaks = seq(floor(min(c(mz(object1), mz(object2)))),
                                     ceiling(max(c(mz(object1), mz(object2)))),
                                     by = binSize)) {
  breaks <- breaks_Spectra(object1, object2,
                           binSize = binSize, breaks = breaks)
  list(bin_Spectrum(object1, breaks = breaks),
       bin_Spectrum(object2, breaks = breaks))
}

#' calculate similarity between spectra (between their intensity profile)
#' @param x spectrum1 (MSnbase::Spectrum)
#' @param y spectrum2 (MSnbase::Spectrum)
#' @param fun similarity function (must take two spectra and ... as arguments)
#' @param ... further arguments passed to "fun"
#' @return double, similarity score
#' @noRd
compare_Spectra <- function(x, y,
                            fun=c("common", "cor", "dotproduct"),
                            ...) {
  if (is.character(fun)) {
    fun <- match.arg(fun)
    if (fun == "cor" || fun == "dotproduct") {
      binnedSpectra <- bin_Spectra(x, y, ...)
      inten <- lapply(binnedSpectra, intensity)
      return(do.call(fun, inten))
    } else if (fun == "common") {
      return(numberOfCommonPeaks(x, y, ...))
    }
  } else if (is.function(fun)) {
    return(fun(x, y, ...))
  }
  return(NA)
}

estimateNoise_Spectrum <- function(object,
                                   method = c("MAD", "SuperSmoother"),
                                   ignoreCentroided = FALSE, ...) {
  if (isEmpty(object)) {
    warning("Your spectrum is empty. Nothing to estimate.")
    return(matrix(NA, nrow = 0L, ncol = 2L,
                  dimnames = list(c(), c("mz", "intensity"))))
  }

  if (!ignoreCentroided && centroided(object)) {
    warning("Noise estimation is only supported for profile spectra.")
    return(matrix(NA, nrow = 0L, ncol = 2L,
                  dimnames = list(c(), c("mz", "intensity"))))
  }

  noise <- MALDIquant:::.estimateNoise(mz(object), intensity(object),
                                       method = match.arg(method), ...)
  cbind(mz=mz(object), intensity=noise)
}

pickPeaks_Spectrum <- function(object, halfWindowSize = 2L,
                               method = c("MAD", "SuperSmoother"),
                               SNR = 0L, ignoreCentroided = FALSE,
                               ...) {
    if (isEmpty(object)) {
        warning("Your spectrum is empty. Nothing to pick.")
        return(object)
    }

    if (!ignoreCentroided && centroided(object, na.fail = TRUE))
        return(object)

    ## estimate noise
    noise <- estimateNoise_Spectrum(object, method = method,
                                    ignoreCentroided = ignoreCentroided,
                                    ...)[, 2L]

    ## find local maxima
    isLocalMaxima <- MALDIquant:::.localMaxima(intensity(object),
                                               halfWindowSize = halfWindowSize)

    ## include only local maxima which are above the noise
    isAboveNoise <- object@intensity > (SNR * noise)

    peakIdx <- which(isAboveNoise & isLocalMaxima)

    object@mz <- object@mz[peakIdx]
    object@intensity <- object@intensity[peakIdx]
    object@peaksCount <- length(peakIdx)
    object@tic <- sum(intensity(object))
    object@centroided <- TRUE

    if (validObject(object)) {
        return(object)
    }
}

smooth_Spectrum <- function(object,
                            method = c("SavitzkyGolay", "MovingAverage"),
                            halfWindowSize = 2L, ...) {

    if (!peaksCount(object)) {
        warning("Your spectrum is empty. Nothing to change.")
        return(object)
    }
    method <- match.arg(method)
    switch(method,
           "SavitzkyGolay" = {
               fun <- MALDIquant:::.savitzkyGolay
           },
           "MovingAverage" = {
               fun <- MALDIquant:::.movingAverage
           })
    object@intensity <- fun(object@intensity,
                            halfWindowSize = halfWindowSize,
                            ...)
    isBelowZero <- object@intensity < 0
    if (any(isBelowZero)) {
        warning("Negative intensities generated. Replaced by zeros.")
        object@intensity[isBelowZero] <- 0
    }
    object@tic <- sum(intensity(object))
    if (validObject(object))
        return(object)
}


## A fast validity check that desn't check the validity of all
## inherited/inheriting objects. See
## https://github.com/lgatto/MSnbase/issues/184#issuecomment-274058543
## for details and background
## Some small performance improvements:
## o direct access of slots.
## o is.unsorted instead of any(diff(mz(object)) < 0)
validSpectrum <- function(object) {
    msg <- validMsg(NULL, NULL)
    if (any(is.na(object@intensity)))
        msg <- validMsg(msg, "'NA' intensities found.")
    if (any(is.na(object@mz)))
        msg <- validMsg(msg, "'NA' M/Z found.")
    if (any(object@intensity < 0))
        msg <- validMsg(msg, "Negative intensities found.")
    if (any(object@mz < 0))
        msg <- validMsg(msg, "Negative M/Z found.")
    if (length(object@mz) != length(object@intensity))
        msg <- validMsg(msg, "Unequal number of MZ and intensity values.")
    if (length(object@mz) != peaksCount(object))
        msg <- validMsg(msg, "Peaks count does not match up with number of MZ values.")
    if (is.unsorted(object@mz))
        msg <- validMsg(msg, "MZ values are out of order.")
    if (is.null(msg)) TRUE
    else stop(msg)
}

#' @description `.spectrum_header` extracts the header information from a
#'     `Spectrum` object and returns it as a named numeric vector.
#'
#' @note We can not get the following information from Spectrum
#' objects:
#' - ionisationEnergy
#' - mergedResultScanNum
#' - mergedResultStartScanNum
#' - mergedResultEndScanNum
#' 
#' @param x `Spectrum` object.
#'
#' @return A named `numeric` with the following fields:
#' - acquisitionNum
#' - msLevel
#' - polarity
#' - peaksCount
#' - totIonCurrent
#' - retentionTime
#' - basePeakMZ
#' - collisionEnergy
#' - ionisationEnergy
#' - lowMZ
#' - highMZ
#' - precursorScanNum
#' - precursorMZ
#' - precurorCharge
#' - precursorIntensity
#' - mergedScan
#' - mergedResultScanNum
#' - mergedResultStartScanNum
#' - mergedResultEndScanNum
#' - injectionTime
#' 
#' @author Johannes Rainer
#'
#' @md
#'
#' @noRd
.spectrum_header <- function(x) {
    res <- c(acquisitionNum = acquisitionNum(x),
             msLevel = msLevel(x),
             polarity = polarity(x),
             peaksCount = peaksCount(x),
             totIonCurrent = tic(x),
             retentionTime = rtime(x),
             basePeakMZ = mz(x)[which.max(intensity(x))][1],
             basePeakIntensity = max(intensity(x)),
             collisionEnergy = 0,
             ionisationEnergy = 0,      # How to get that?
             lowMZ = min(mz(x)),
             highMZ = max(mz(x)),
             precursorScanNum = 0,
             precursorMZ = 0,
             precursorCharge = 0,
             precursorIntensity = 0,
             mergedScan = 0,
             mergedResultScanNum = 0,   # ???
             mergedResultStartScanNum = 0, # ???
             mergedResultEndScanNum = 0,   # ???
             injectionTime = 0            # Don't have that
             )
    if (msLevel(x) > 1) {
        res["collisionEnergy"] <- collisionEnergy(x)
        res["precursorScanNum"] <- precScanNum(x)
        res["precursorMZ"] <- precursorMz(x)
        res["precursorCharge"] <- precursorCharge(x)
        res["precursorIntensity"] <- precursorIntensity(x)
        res["mergedScan"] <- x@merged
    }
    res
}

