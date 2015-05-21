function [A,b] = update_spatial_components(Y,C,f,A_,P)

% update spatial components and background through BPDN

[d,T] = size(Y);
if ~isfield(P,'dist'); dist = 3; else dist = P.dist; end
if ~isfield(P,'d1'); d1 = sqrt(d); else d1 = P.d1; end
if ~isfield(P,'d2'); d2 = sqrt(d); else d2 = P.d2; end
if ~isfield(P,'min_size'); min_size = 8^2; else min_size = P.min_size; end
if ~isfield(P,'max_size'); max_size = 3^2; else max_size = P.max_size; end
if ~isfield(P,'med_filt'); med_filt = [3,3]; else med_filt = P.med_filt; end
if ~isfield(P,'thres'); thres = 0.2; else thres = P.thres; end
if ~isfield(P,'show_sum'); show_sum = P.show_sum; else show_sum = 0; end
if ~isfield(P,'interp'); Y_interp = P.interp; else Y_interp = sparse(d,T); end

Coor.x = kron(ones(d2,1),(1:d1)');
Coor.y = kron((1:d2)',ones(d1,1));

nr = size(C,1);       % number of neurons

if ~(dist==Inf)       % determine search area for each neuron
   cm = zeros(nr,2);  % vector for center of mass
   Vr = cell(nr,1);
   IND = zeros(d,nr); % indicator for distance								   
    cm(:,1) = Coor.x'*A_(:,1:nr)./sum(A_(:,1:nr));
    cm(:,2) = Coor.y'*A_(:,1:nr)./sum(A_(:,1:nr));
    for i = 1:nr
        Vr{i} = ([Coor.x - cm(i,1), Coor.y - cm(i,2)]'*spdiags(A_(:,i),0,d,d)*[Coor.x - cm(i,1), Coor.y - cm(i,2)])/sum(A_(:,i));
        [V,D] = eig(Vr{i});
        cor = [Coor.x - cm(i,1),Coor.y - cm(i,2)];
        d11 = min(min_size^2,max(max_size^2,D(1,1)));
        d22 = min(min_size^2,max(max_size^2,D(2,2)));
        IND(:,i) = sqrt((cor*V(:,1)).^2/d11 + (cor*V(:,2)).^2/d22)<=dist;
    end
end
Cf = [C;f];
    A = [zeros(d,nr),zeros(d,size(f,1))];
    sA = zeros(d1,d2);
    for px = 1:d   % estimate spatial components
        fn = ~isnan(Y(px,:));       % identify missing data
        if dist == Inf
            [~, ~, a, ~] = lars_regression_noise(Y(px,fn)', Cf(:,fn)', 1, P.sn(px)^2*T);
            A(px,:) = a';
            sA(px) = sum(a);
        else
            ind = find(IND(px,:));
            if ~isempty(ind);
                ind2 = [ind,nr+(1:size(f,1))];
                [~, ~, a, ~] = lars_regression_noise(Y(px,fn)', Cf(ind2,fn)', 1, P.sn(px)^2*T);
                A(px,ind2) = a';
                sA(px) = sum(a);
            end
        end
        if show_sum
            if mod(px,d1) == 0;
               figure(20); imagesc(sA); axis square;  
               title(sprintf('Sum of spatial components (%i out of %i columns done)',round(px/d1),d2)); drawnow;
            end
        end
    end
    A(isnan(A))=0;
for i = 1:nr   % perform median filtering on extracted components
    I_temp = medfilt2(full(reshape(A(:,i),d1,d2)),med_filt);
    acp = intersect(find(I_temp(:)),find(A(:,i)));
    A(:,i) = sparse(acp,1,A(acp,i),d,1); %I_temp(:);
end
    A = sparse(A);
    
    Ath = A;       % perform thresholding on extracted components 
    for i = 1:nr
        Ath(Ath(:,i)<thres*max(Ath(:,i)),i) = 0;
        BW = bwlabel(full(reshape(Ath(:,i),d1,d2)));
        ml = max(BW(:));
        ln = zeros(ml,1);
        for j = 1:ml
            ln(j) = length(find(BW==j));
        end
        [~,ind] = max(ln);
        Ath(BW(:)~=ind,i) = 0;
    end
    A = Ath;
    
    fprintf('Updated spatial components \n');
    
    ff = find(sum(A)==0);
    if ~isempty(ff)
        nr = nr - length(ff);
        A(:,ff) = [];
        C(ff,:) = [];
    end
    
    if nnz(Y_interp);
        ff = find(Y_interp);
        Y(ff) = Y_interp(ff);
    end
    
    Y_res = Y - A(:,1:nr)*C(1:nr,:);
    A_bas = max(Y_res*f'/norm(f)^2,0);
    b = A_bas;
    A = A(:,1:nr);