#####################################################################
#
# Original:
# R code for reproducing the experiments in 
# (Roos, Oulasvirta, "An Extended Framework for Measuring the
# Information Capacity of the Human Motor System")
#
# code by Teemu Roos, Feb 15, 2011
# teemu.roos (at) cs.helsinki.fi
#
# Current version:
# Modified for more general use and added PCA functionality
# by Laura Leppänen (research assistant), September 2011
# laura.leppanen (at) cs.helsinki.fi
#
# New method of calculating throughput using residuals of residuals
# added by Arttu Modig (research assistant), September 2011
# arttu.modig (at) aalto.fi
#
# Data needs to be aligned temporally before being evaluated
# for information capacity. To align, we recommend Canonical
# Time Warping, from www.humansensing.cs.cmu.edu/projects/ctwCode.html
#
#####################################################################

options(width=Sys.getenv("COLUMNS"))

use_warnings = FALSE
twopie = 2*pi*exp(1)

# Return stochastic complexity of the observed sequence given predictor features
# (sometimes containing side information from another sequence, but usually only
# shifted data from the same sequence). The number of columns in sequence_predictors
# is always a multiple of the number of columns in observed_sequence because
# the side information always contains all the same features.
evaluate_SC <- function(sequence_predictors, observed_sequence) {
    frames <- nrow(observed_sequence)
    num_features <- ncol(observed_sequence)
    feature_code_length <- array(0,ncol(observed_sequence))
    total_code_length <- 0
    residual_sums = list()
    for (i in 1:num_features) {
        # extract regressors depending on the input size
        if (ncol(sequence_predictors) == num_features) {
            predictors <- qr(cbind(matrix(1,frames,1), sequence_predictors[, i]))
            k = 3
        }
        if (ncol(sequence_predictors) == 2 * num_features) {
            predictors <- qr(cbind(matrix(1,frames,1), sequence_predictors[, i], sequence_predictors[, num_features+i]))
            k = 4
        }
        if (ncol(sequence_predictors) == 3 * num_features) {
            predictors <- qr(cbind(matrix(1,frames,1), sequence_predictors[, i], sequence_predictors[, num_features+i],
                        sequence_predictors[, 2*num_features+i]))
            k = 5
        }
        if (ncol(sequence_predictors) == 4 * num_features) {
            predictors <- qr(cbind(matrix(1,frames,1), sequence_predictors[, i], sequence_predictors[, num_features+i],
                        sequence_predictors[, 2*num_features+i],
                        sequence_predictors[, 3*num_features+i]))
            k = 6
        }

        res <- qr.resid(predictors, observed_sequence[, i])

        # warning about possibly too low variance
        if (use_warnings)
            if (sum(res^2) < .01) print(c(i,sum(res^2)))

        residual_sum <- sum(res^2)
        residual_sums[[i]] <- residual_sum

        # Rissanen's classic two-part MDL code-length (feel free
        # to replace by more advanced universal code).
        MDL <-  frames/2*log(twopie*residual_sum/frames) + k/2*log(frames)

        feature_code_length[i] <- MDL
        total_code_length <- total_code_length + MDL
    }
    return(list(total = total_code_length, feature = feature_code_length,
        residual_sums = residual_sums))
}

# Return residuals from the AR(2) model as a list where each element is the
# residual vector for the corresponding feature, given the observed sequence
# and some predictor features (shifted data from the observed sequence).
evaluate_residuals <- function(sequence_predictors, observed_sequence) {
    frames <- nrow(observed_sequence)
    num_features <- ncol(observed_sequence)
    residuals = list()
    # extract regressors depending on the input size
    for (i in 1:num_features) {
        if (ncol(sequence_predictors) == num_features)
            predictors <- qr(cbind(matrix(1,frames,1), sequence_predictors[, i]))
        if (ncol(sequence_predictors) == 2 * num_features)
            predictors <- qr(cbind(matrix(1,frames,1), sequence_predictors[, i], sequence_predictors[, num_features+i]))

        residuals[[i]] <- qr.resid(predictors, observed_sequence[, i])
    }
    return(residuals)
}

evaluate_residual_shared_information <- function(residuals_a, residuals_b, n) {
    total_shared <- 0
    total_RSS <- 0
    total_RSS_residual <- 0
    feature_shared <- array(0,ncol(a))

    for (i in 1:length(residuals_a)) {
        lm.ra = lm(residuals_a[[i]] ~ residuals_b[[i]])
        residuals = resid(lm.ra)

        RSS <- sum(residuals_a[[i]]^2)
        RSS_residual <- sum(residuals^2)
        total_RSS <- total_RSS + RSS
        total_RSS_residual <- total_RSS_residual + RSS_residual

        shared_information <- (n/2*log(RSS/RSS_residual) - log(n)/2)

        feature_shared[i] <- shared_information
        total_shared <- total_shared + shared_information
    }

    return(list(total_shared = total_shared, feature_shared = feature_shared,
        total_RSS = total_RSS, total_RSS_residual = total_RSS_residual))
}

shared_information_by_residuals <- function(a,b,index) {
    n <- nrow(a) - index

    residuals_a <- evaluate_residuals(cbind(a[1:n,],a[1:n+index-1,]), a[1:n+index,])
    residuals_b <- evaluate_residuals(cbind(b[1:n,],b[1:n+index-1,]), b[1:n+index,])

    results <- evaluate_residual_shared_information(residuals_a, residuals_b, n)

    quotient <- results$total_RSS / results$total_RSS_residual

    return(list(n = n, total_shared = results$total_shared,
        feature_shared = results$feature_shared, total_RSS = results$total_RSS,
        total_RSS_residual = results$total_RSS_residual, quotient = quotient))
}

# Complexity of a single (multivariate) sequence
SC <- function(a, index) {
    n <- nrow(a)-index
    if (n < 1)
        return(list(n = 0,k = 1,cl = 0,rate = 0))

    SC <- evaluate_SC(cbind(a[1:n,],a[1:n+index-1,]), a[1:n+index,])
    complexity <- SC$total
    feature_complexity <- SC$feature
    residual_sums <- SC$residual_sums
    return(list(n = n, complexity = complexity, rate = complexity/n,
        feature_complexity = feature_complexity, residual_sums = residual_sums))
}

# Complexity of a (multivariate) sequence given another
SCcond <- function(a,b, index) {
    n <- min(nrow(a), nrow(b))-index
    SC <- evaluate_SC(cbind(a[1:n,],a[1:n+index-1,],b[1:n+index,]), a[1:n+index,])
    complexity <- SC$total
    feature_complexity <- SC$feature
    residual_sums <- SC$residual_sums
    return(list(n = n, complexity = complexity, rate = complexity/n,
        feature_complexity = feature_complexity, residual_sums = residual_sums))
}

# Removes duplicated rows from both sequences a and b
# either symmetrically or asymmetrically.
#
# Returns the altered sequences as a list with two elements.
remove_duplicate_frames <- function(a, b, symmetric = FALSE) {
    skipa <- rowSums((a[2:nrow(a),]-a[1:(nrow(a)-1),])^2) < 0.001
    skipa <- c(FALSE, skipa)
    if (symmetric) {
        skipb <- matrix(FALSE, nrow(b))
        skipb <- rowSums((b[2:nrow(b),]-b[1:(nrow(b)-1),])^2) < 0.001
        skipb <- c(FALSE, skipb)
        skip <- skipa | skipb
    }
    else
        skip <- skipa

    a <- a[!skip,]
    b <- b[!skip,]

    return(list(a, b))
}

# Performs normalization on the features of sequence a.
# Returns the altered sequence.
normalize_features <- function(a) {
    a <- t(apply(a,1,'-',apply(a,2,mean)))
    a <- t(apply(a,1,'/',sqrt(apply(a,2,var))))
    a[is.nan(a)]<-0

    return(a)
}

# Add noise to the features of a matrix.
add_noise_to_features <- function(a, noise_coeff) {
    features <- ncol(a)
    for (k in 1:features) {
        feature_sdev <- sqrt(var(a[,k]))
        a[,k] <- a[,k] + noise_coeff * feature_sdev * rnorm(nrow(a))
    }
    return(a)
}

# Returns a matrix containing the chosen most significant eigenvectors
pca <- function(data) {
    principal_components <- prcomp(data, retx = TRUE, center = TRUE, scale. = TRUE)

    sum <- 0
    eigenvectors <- 0
    threshold <- 0.9*sum(principal_components$sdev**2)
    for (k in 1:length(principal_components$sdev)) {
        sum <- sum + principal_components$sdev[k]**2
        eigenvectors <- k
        if (sum >= threshold)
            break
    }

    eigenvectors <- principal_components$rotation[,1:eigenvectors]

    return(eigenvectors)
}

# Returns throughput determined by residuals of residuals.
residual_throughput <- function(a, b, fps = 120, features = FALSE, index = 2) {
    lena <- nrow(a)

    SI <- shared_information_by_residuals(a, b, index)
    total_SI <- SI$total_shared
    throughput <- total_SI / lena * fps / log(2.0)

    if (features) {
        feature_SI <- shared_information$feature_shared
        feature_throughputs <- feature_SI / lena * fps / log(2.0)
        return(list(total_SI = total_SI, throughput = throughput,
            feature_SI = feature_SI, feature_throughputs = feature_throughputs,
            RSS = SI$total_RSS, RSS_residual = SI$total_RSS_residual,
            quotient = SI$quotient))
    }

    return(list(throughput = throughput, total_SI = total_SI,
        RSS = SI$total_RSS, RSS_residual = SI$total_RSS_residual,
        quotient = SI$quotient))
}

# Returns throughput calculated in the manner described in the original
# arxiv paper draft.
original_throughput <- function(a, b, fps = 120, features = FALSE, index = 2) {
    length_a <- nrow(a)
    SC_a <- SC(a, index)
    SC_a_b <- SCcond(a, b, index)

    complexity_of_a <- SC_a$complexity
    feature_complexity_of_a <- SC_a$feature_complexity

    complexity_of_a_cond_b <- SC_a_b$complexity
    feature_complexity_of_a_cond_b <- SC_a_b$feature_complexity

    shared_information <- complexity_of_a - complexity_of_a_cond_b
    throughput <- shared_information / length_a * fps / log(2.0)

    RSS_a <- sum(unlist(SC_a$residual_sums))
    RSS_a_cond_b <- sum(unlist(SC_a_b$residual_sums))
    quotient <- RSS_a / RSS_a_cond_b

    if (features) {
        feature_shared_informations <- array(0,ncol(a))
        feature_throughputs <- array(0,ncol(a))
        for (k in 1:ncol(a)) {
            feature_shared_informations[k] <- (feature_complexity_of_a[k] -
                feature_complexity_of_a_cond_b[k])
            feature_throughputs[k] <- (feature_complexity_of_a[k] -
                feature_complexity_of_a_cond_b[k]) / length_a * fps / log(2.0)
        }

        return(list(total_SI = shared_information,
            throughput = throughput,
            feature_SI = feature_shared_informations,
            feature_throughputs = feature_throughputs, RSS = RSS_a,
            RSS_residual = RSS_a_cond_b, quotient = quotient))
    }

    return(list(total_SI = shared_information, throughput = throughput,
        RSS = RSS_a, RSS_residual = RSS_a_cond_b, quotient = quotient))
}

# Calculate throughput for a given pair of matrices.
throughput <- function(a, b, fps = 120, pca = FALSE, residuals = TRUE,
    features = FALSE, index = 2) {

    lena <- nrow(a)

    if (pca) {
        eigenvectors <- pca(a)
        a <- a %*% eigenvectors
        b <- b %*% eigenvectors
    }

    if (residuals)
        return(residual_throughput(a, b, fps = fps,
            features = features, index = index))

    return(original_throughput(a, b, fps = fps , features = features, index = index))
}

# Calculate throughput for a given pair of files.
#
# See the dir_throughput function for descriptions of optional parameters.
pair_throughput <- function(filename1, filename2, fps = 120, pca = FALSE,
    amc = FALSE, residuals = TRUE, features = FALSE, warnings = FALSE,
    noise = 0, index = 2, symmetric = FALSE, normalize = TRUE, duplicates = FALSE) {
        
    use_warnings <<- warnings

    a <- read.table(filename1)
    b <- read.table(filename2)

    # Eliminate features with zero variance in AMC format data, usually the
    # fingers of both hands.
    if (amc) {
        a$V34=NULL; a$V46=NULL;
        b$V34=NULL; b$V46=NULL;
    }

    if (!duplicates) {
        data <- remove_duplicate_frames(a, b, symmetric)
        a <- data[[1]]
        b <- data[[2]]
    }

    if (noise > 0)
        a <- add_noise_to_features(a, noise)
    
    if (normalize) {
        a <- normalize_features(a)
        b <- normalize_features(b)
    }

    use_warnings <<- FALSE
    return(throughput(a, b, fps = fps, pca = pca, residuals = residuals,
        features = features, index = index))
}

# For a given pair of files, calculate residual sums and throughputs with
# different indices for the second AR time step.
#
# See dir_throughput for optional parameters. The index parameter that
# supplies the step size for the AR model is replaced with three new
# parameters:
#
# start_step    the starting value for the AR model step size (default 2)
# end_step      the end value for the AR model step size (default 120)
# interval      the interval between step sizes in the trials (default 1)
evaluate_RSS <- function(filename1, filename2, fps = 120, pca = FALSE, amc = FALSE,
    residuals = TRUE, features = FALSE, warnings = FALSE, noise = 0, symmetric = FALSE,
    start_index = 2, end_index = 120, interval = 1) {

    size <- (end_index-start_index)/step_index+1
    results <- array(0, c(size, 5));
    colnames(results) <- c("index","RSS","RSS_conditional","RSS / RSS_cond","TP")
    n <- 1
    
    for (index in seq(start_index, end_index, interval)) {
        print(index) # To see the proceeding

        TP <- pair_throughput(filename1, filename2, fps = fps, pca = pca, amc = amc,
            residuals = residuals, features = features, warnings = warnings,
            noise = noise, index = index, symmetric = symmetric)
        
        results[n,1] <- index
        results[n,2] <- TP$RSS
        results[n,3] <- TP$RSS_residual
        results[n,4] <- TP$quotient
        results[n,5] <- TP$throughput
        n <- n+1
    }

    return(results)
}

# Calculate throughput for all aligned sequence pairs in the directory (by
# default the current working directory).
#
# The function assumes that the original amc or coordinate files are in the
# working directory. (Note: all files should be for the same test subject!)
# Files should be named <sequence number>.txt, e.g. "15.txt".
#
# The aligned data should reside in a subdirectory (by default "aligneddata")
# in files that are named in the following way:
#         <seq1 #>_ali_<seq2 #>.txt
# Example: "14_ali_15.txt".
#
# Parameters:
# - subdir     subdirectory that contains the aligned data (default "aligneddata")
# - fps        frames per second
# - pca        use principal components analysis
# - amc        input data is in AMC format
# - residuals  use residuals of residuals to determine complexities
# - features   also calculate throughput for individual features
# - warnings   print warnings of low residual variance (to debug NaN results)
# - noise      noise coefficient (default 0)
# - index      the step variable for the AR(2) model in the "residuals of residuals"
#              method
# - symmetric  remove duplicates symmetrically (default is asymmetric)
dir_throughput <- function(subdir = "aligneddata", fps = 120, pca = FALSE, amc = FALSE,
    residuals = TRUE, features = FALSE, warnings = FALSE, noise = 0, index = 2,
    symmetric = FALSE) {

    if (amc) {
        files <- dir(".", "^[[:digit:]]+.amc$")
    } else
        files <- dir(".", "^[[:digit:]]+.txt$")
    sequences <- length(files)

    total_throughputs <- array(0, c(sequences/2, 2))
    feature_throughputs <- array(list(NULL), c(sequences/2, 2))

    for (i in 1:(sequences/2)) {
        j = 2 * i - 1
        k = j + 1
        file1 <- sprintf("%s/%d_ali_%d.txt", subdir, j, k)
        file2 <- sprintf("%s/%d_ali_%d.txt", subdir, k, j)

        results <- pair_throughput(file1, file2, fps = fps, pca = pca,
            amc = amc, res = residuals, features = features, warnings = warnings,
            noise = noise, index = index, symmetric = symmetric, normalize = normalize)
        inverse_results <- pair_throughput(file2, file1, fps = fps, pca = pca,
            amc = amc, res = residuals, features = features, warnings = warnings,
            noise = noise, index = index, symmetric = symmetric, normalize = normalize)

        total_throughputs[i,1] <- results$throughput
        total_throughputs[i,2] <- inverse_results$throughput

        if (features) {
            feature_throughputs[i,1] <- list(results$feature_throughputs)
            feature_throughputs[i,2] <- list(inverse_results$feature_throughputs)
        }
    }

    if (features) {
        return(list(total = total_throughputs, feature = feature_throughputs))
    } else
        return(list(total = total_throughputs))
}
