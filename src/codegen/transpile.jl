export transpile 

transpile(scope::Scope, s::Scalar) = s.element
transpile(scope::Scope, var::WGPUVariable) = var.dataType == Any ? :($(var.sym)) : :($(var.sym)::$(var.dataType))
transpile(scope::Scope, lhs::LHS) = transpile(scope, lhs.variable)
transpile(scope::Scope, var::WGPUVariable, ::Val{true}) = :(@var $(transpile(scope, var)))
transpile(scope::Scope, var::WGPUVariable, ::Val{false}) = :($(var.sym))
transpile(scope::Scope, rhs::RHS) = transpile(scope, rhs.rhsExpr)
transpile(scope::Scope, binOp::BinaryOp) = transpile(scope, binOp, Val(binOp.op))

# for each op in [:+, :-, :*, :\, :<, :>, :<=, :>=, :==, :+=, :-=]
transpile(scope::Scope, binOp::BinaryOp, op::Val{:+}) = :($(transpile(scope, binOp.left)) + $(transpile(scope, binOp.right)))
transpile(scope::Scope, binOp::BinaryOp, op::Val{:-}) = :($(transpile(scope, binOp.left)) - $(transpile(scope, binOp.right)))
transpile(scope::Scope, binOp::BinaryOp, op::Val{:*}) = :($(transpile(scope, binOp.left)) * $(transpile(scope, binOp.right)))
transpile(scope::Scope, binOp::BinaryOp, op::Val{:/}) = :($(transpile(scope, binOp.left)) / $(transpile(scope, binOp.right)))
transpile(scope::Scope, binOp::BinaryOp, op::Val{:<}) = :($(transpile(scope, binOp.left)) < $(transpile(scope, binOp.right)))
transpile(scope::Scope, binOp::BinaryOp, op::Val{:>}) = :($(transpile(scope, binOp.left)) > $(transpile(scope, binOp.right)))
transpile(scope::Scope, binOp::BinaryOp, op::Val{:(<=)}) = :($(transpile(scope, binOp.left)) <= $(transpile(scope, binOp.right)))
transpile(scope::Scope, binOp::BinaryOp, op::Val{:(>=)}) = :($(transpile(scope, binOp.left)) >= $(transpile(scope, binOp.right)))
transpile(scope::Scope, binOp::BinaryOp, op::Val{:(==)}) = :($(transpile(scope, binOp.left)) == $(transpile(scope, binOp.right)))
transpile(scope::Scope, binOp::BinaryOp, op::Val{:(+=)}) = :($(transpile(scope, binOp.left)) += $(transpile(scope, binOp.right)))
transpile(scope::Scope, binOp::BinaryOp, op::Val{:(-=)}) = :($(transpile(scope, binOp.left)) -= $(transpile(scope, binOp.right)))

function transpile(scope::Scope, a::AssignmentExpr)
	lExpr = transpile(scope, a.lhs)
	rExpr = transpile(scope, a.rhs)
	if @capture(lExpr, @var_(v_))
		return :(@var $v =  $rExpr)
	else
		return :($lExpr =  $rExpr)
	end
end

function transpile(scope::Scope, cExpr::CallExpr)
	return Expr(:call, transpile(scope, cExpr.func), map(x -> transpile(scope, x), cExpr.args)...)
end

function transpile(scope::Scope, idxExpr::IndexExpr)
	return Expr(:ref, transpile(scope, idxExpr.sym), transpile(scope, idxExpr.idx))
end

transpile(scope::Scope, idxExpr::IndexExpr, ::Val{true}) = transpile(scope, idxExpr::IndexExpr)
transpile(scope::Scope, idxExpr::IndexExpr, ::Val{false}) = error("This variable cannot be indexed")

function transpile(scope::Scope, acsExpr::AccessExpr)
	return Expr(:., transpile(scope, acsExpr.sym), QuoteNode(transpile(scope, acsExpr.field)))
end

transpile(scope::Scope, declExpr::DeclExpr) = Expr(:(::), map(x -> transpile(scope, x), (declExpr.sym, declExpr.dataType))...)
transpile(scope::Scope, ::Type{T}) where T = :($T)

transpile(scope::Scope, typeExpr::TypeExpr) = Expr(
	:curly, transpile(scope, typeExpr.sym), 
	map(x -> transpile(scope, x), typeExpr.types)...
)

function transpile(scope::Scope, rblock::RangeBlock)
	(start, step, stop) = map(x -> transpile(scope, x), (rblock.start, rblock.step, rblock.stop))
	range = :($start:$step:$stop)
	block = map(x -> transpile(scope, x), rblock.block)
	idx = transpile(scope, rblock.idx)
	return Expr(:for, Expr(:(=), idx, range), quote $(block...) end)
end

function transpile(scope::Scope, ifblock::IfBlock)
	c = transpile(scope, ifblock.cond)
	block = map(x -> transpile(scope, x), ifblock.block)
	return Expr(:if, c, quote $(block...) end)
end

function transpile(scope::Scope, funcblk::FuncBlock)
	fn = transpile(scope, funcblk.fname)
	fa = map(x -> transpile(scope, x), funcblk.fargs)
	fb = map(x -> transpile(scope, x), funcblk.fbody)
	return Expr(:function, Expr(:call, fn, fa...), quote $(fb...) end)
end

function transpile(scope::Scope, computeBlk::ComputeBlock)
	fn = transpile(scope::Scope, computeBlk.fname)
	fa = map(x -> transpile(scope, x), computeBlk.fargs)
	fb = map(x -> transpile(scope, x), computeBlk.fbody)
	ta = map(x -> transpile(scope, x), computeBlk.Targs)
	return Expr(:function, Expr(:where, Expr(:call, fn, fa...), ta...), quote $(fb...) end) |> MacroTools.striplines
end
